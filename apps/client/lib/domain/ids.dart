const String defaultBookId = 'book_default';

String accountId(String bookId, String key) => '$bookId:$key';

String accountKeyCash(String bookId) => accountId(bookId, 'acc_cash');
String accountKeyBank(String bookId) => accountId(bookId, 'acc_bank');
String accountKeyFood(String bookId) => accountId(bookId, 'acc_food');
String accountKeyTransport(String bookId) => accountId(bookId, 'acc_transport');
String accountKeySalary(String bookId) => accountId(bookId, 'acc_salary');
