# Phase BE-2：服务端 Ledger

* 分支：`mvp/phase-be-2-ledger`
* ADR：BE-008/010

## 目标

复式写入、不平衡拒绝、version CAS。

## 验收

- [x] 领域层拒绝不平衡
- [x] API 创建交易校验分录和为 0
