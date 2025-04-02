namespace java dev.vality.liminator
namespace erlang liminator.liminator

typedef string LimitId

/* Наименование лимита (например, limit.card.day.777) */
typedef string LimitName

/* ИД операции изменения значения (например, invoice.1) */
typedef string OperationId

typedef map<string, string> Context

typedef i64 Value

/* Временная метка операции epochmills */
typedef i64 Timestamp

exception LimitNotFound {}
exception OperationNotFound {}
exception OperationAlreadyInFinalState {}
exception DuplicateOperation {}
exception DuplicateLimitName {}
exception LimitsValuesReadingException {}
exception InvalidRequest {}

struct LimitChange {
    1: optional LimitId limit_id
    2: required LimitName limit_name
    3: required Value value
    4: optional Context context
}

struct LimitRequest {
    1: required OperationId operation_id
    2: required list<LimitChange> limit_changes
}

struct LimitResponse {
    1: optional LimitId limit_id
    2: required LimitName limit_name
    3: required Value commit_value
    /*
    * Суммарное значение всех коммитов, всех текущих холдов и нового холда в обработке
    * */
    4: required Value total_value
}

service LiminatorService {
    /* Добавить значение, создать если нет */
    list<LimitResponse> Hold(LimitRequest request)
        throws (1: LimitNotFound ex1, 2: DuplicateOperation ex2, 3: OperationAlreadyInFinalState ex3)

    /* Применить значение */
    void Commit(LimitRequest request) throws (1: LimitNotFound ex1, 2: OperationNotFound ex2)

    /* Отменить добавление */
    void Rollback(LimitRequest request) throws (1: LimitNotFound ex1, 2: OperationNotFound ex2, 3: InvalidRequest ex3)

    /* Получить значения лимитов */
    list<LimitResponse> Get(LimitRequest request) throws (1: LimitNotFound ex1, 2: LimitsValuesReadingException ex2)

    /* Получить актуальные значения лимитов на текущий момент */
    list<LimitResponse> GetLastLimitsValues(list<LimitName> limit_names)
        throws (1: LimitNotFound ex1, 2: LimitsValuesReadingException ex2)
}