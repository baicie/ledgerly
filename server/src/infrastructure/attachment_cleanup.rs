use sqlx::PgPool;

use crate::config::Config;
use crate::infrastructure::object_store;

const CLEANUP_BATCH_SIZE: i64 = 200;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct AttachmentCleanupReport {
    pub scanned: usize,
    pub deleted: usize,
    pub failed: usize,
}

pub async fn purge_stale_attachments(
    pool: &PgPool,
    config: &Config,
) -> anyhow::Result<AttachmentCleanupReport> {
    let ttl_hours = config.attachment_pending_ttl_hours.max(1) as i64;
    let mut tx = pool.begin().await?;
    let rows: Vec<(String, String, String, Option<String>)> = sqlx::query_as(
        "SELECT id, object_key, upload_mode, multipart_upload_id
         FROM attachments
         WHERE upload_status IN ('pending', 'failed')
           AND created_at < now() - ($1::bigint * interval '1 hour')
         ORDER BY created_at, id
         FOR UPDATE SKIP LOCKED
         LIMIT $2",
    )
    .bind(ttl_hours)
    .bind(CLEANUP_BATCH_SIZE)
    .fetch_all(&mut *tx)
    .await?;

    let mut report = AttachmentCleanupReport {
        scanned: rows.len(),
        ..AttachmentCleanupReport::default()
    };
    for (attachment_id, object_key, upload_mode, multipart_upload_id) in rows {
        let cleanup = if upload_mode == "multipart" {
            match object_store::abort_multipart_for_config(
                config,
                &object_key,
                multipart_upload_id.as_deref(),
            )
            .await
            {
                Ok(()) => {
                    // The final object should not exist for a pending multipart upload,
                    // but deletion is idempotent if a previous complete partially failed.
                    object_store::delete_object_for_config(config, &object_key).await
                }
                Err(error) => Err(error),
            }
        } else {
            object_store::delete_object_for_config(config, &object_key).await
        };
        match cleanup {
            Ok(()) => {
                sqlx::query("DELETE FROM attachments WHERE id=$1")
                    .bind(&attachment_id)
                    .execute(&mut *tx)
                    .await?;
                report.deleted += 1;
            }
            Err(_) => {
                report.failed += 1;
            }
        }
    }
    tx.commit().await?;
    crate::metrics::record_attachment_cleanup(report.deleted, report.failed);
    Ok(report)
}
