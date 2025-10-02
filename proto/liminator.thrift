namespace java dev.vality.liminator
namespace erlang liminator.liminator

/**
 * Глобально уникальный идентификатор группы счётчиков, имеющих общее поведение
 * определеяемого внешней системой.
 * Далее будет использоваться понятие "лимит" для его обозначения.
 */
typedef string LimitId

/**
 * Наименование лимита. Например, "limit.card.day.777".
 * Это глобально уникальный идентификатор непосредственного счётчика, значение
 * которого может прирастать, но никогда не убывать.
 */
typedef string LimitName

/**
 * Глобально уникальный идентификатор операции которая содержит непосредственные
 * изменения значения счётчиков.
 * Например, "invoice.1".
 */
typedef string OperationId

/**
 * Набор атрибутов характеризующих происхождений изменения счётчика, либо
 * содержащих информацию для интроспекции и аудита.
 */
typedef map<string, string> Context

typedef i64 Value

/**
 * Временная метка операции epochmills.
 */
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

/**
 * Запрос на изменения счётчиков. Далее можно считать эквивалентным понятию
 * "операция" [изменения счётчиков].
 */
struct LimitRequest {
    1: required OperationId operation_id
    2: required list<LimitChange> limit_changes
}

struct LimitResponse {
    1: optional LimitId limit_id
    2: required LimitName limit_name
    /**
     * Значение счётчика согласно только финализированным операциям.
     */
    3: required Value commit_value
    /**
     * Суммарное значение всех коммитов, всех текущих холдов и нового холда в
     * обработке.
     */
    4: required Value total_value
}

/**
 * Это сервис двухстадийного управления неубывающими счётчиками.
 *
 * Для простоты представления в таблице со сценариями вызовов функций каждая
 * операция содержит ровно одно изменение.
 *
 * | Функция             | Оп.  | Счёт  | Изм. | Итог* | Исключение         |
 * |---------------------|------|-------|------|-------|--------------------|
 * | Hold                | op.1 | lim/1 | 1    | 1     | N/A                |
 * | GetLastLimitsValues | N/A  | lim/1 | N/A  | 1     | N/A                |
 * | Rollback            | op.1 | lim/1 | 1    | 0     | N/A                |
 * | Rollback            | op.1 | lim/1 | 1    | 0     | N/A                |
 * | Rollback            | op.1 | lim/1 | 2    | N/A   | OperationNotFound  |
 * |---------------------|------|-------|------|-------|--------------------|
 * | Hold                | op.1 | lim/1 | 1    | N/A   | DuplicateOperation |
 * |---------------------|------|-------|------|-------|--------------------|
 * | Hold                | op.2 | lim/1 | 42   | 42    | N/A                |
 * | Hold                | op.2 | lim/2 | 13   | N/A   | DuplicateOperation |
 * | Commit              | op.2 | lim/1 | 42   | 42    | N/A                |
 * |---------------------|------|-------|------|-------|--------------------|
 * | Hold                | op.3 | lim/2 | 2    | 2     | N/A                |
 * | Hold                | op.4 | lim/2 | 2    | 4     | N/A                |
 * | Commit              | op.4 | lim/2 | 2    | 4     | N/A                |
 * | Rollback            | op.3 | lim/2 | 2    | 2     | N/A                |
 * |---------------------|------|-------|------|-------|--------------------|
 * | Hold                | op.4 | lim/3 | 10   | 10    | N/A                |
 * | Commit              | op.4 | lim/3 | 9    | 9     | N/A                |
 *
 * (*) после, для соотв. счётчика
 */
service LiminatorService {

    /**
     * Начальный шаг двухстадийного процесса по увеличению счётчиков в составе
     * операции.
     * После успешного выполнения этой функции значение для каждого счётчика
     * должно быть увеличено на соответствующее целое число.
     *
     * Например для запроса
     *
     *   LimitRequest(
     *     operation_id: "test-op.1",
     *     limit_changes = [
     *       LimitChange(
     *         limit_name: "test-lim/1",
     *         value: 1
     *       )
     *     ]
     *   )
     *
     * последующий вызов функции получения значения счётчика "test-lim/1" должен
     * сообщить значение `LimitResponse.total_value` которое было увеличено на
     * "1".
     *
     * Если за время выполнения этого вызова другие вызовы изменяли этот
     * счётчик, то это так же должно быть отражено в сообщаемом значении
     * `LimitResponse.total_value`.
     *
     * Вызов этой функции не является идемпотентным, так как в результате её
     * исполнения должен стартовать (или создаваться) новый процесс увеличения
     * счётчиков.
     *
     * FIXME Не понятно зачем исключение `OperationAlreadyInFinalState`,
     * возможно где есть недопонимание.
     */
    list<LimitResponse> Hold(LimitRequest request)
        throws (1: LimitNotFound ex1, 2: DuplicateOperation ex2, 3: OperationAlreadyInFinalState ex3)

    /**
     * Завершающий шаг двухстадийного процесса, подтверждающий изменение
     * счётчика и исключающий возможность выполенения альтернативного
     * завершающего шага отката изменений.
     *
     * В сообщаемой операции для подтверждения допускается отличие значений
     * увеличивающих счётчики в меньшую сторону. То есть от 0 до N, где N - это
     * значение `LimitRequest.limit_changes[].value` в операции с которой начали
     * процесс вызовом функции `Hold(LimitRequest)`.
     *
     * В таком случае это следует считать частичным подтверждением операции и
     * соответствующие изменения счётиков должны меняться не на изначальные
     * значения, а на те что были указаны в этом случае.
     * Так, обнуление значений изменения практически осуществляет эффект
     * завершающего шага отката процесса по этой операции.
     *
     * В остальных случаях с полной идентичностью операции начальной, значения
     * увеличения счётчиков не должны изменяться. А в случае отсутствия иных
     * изменений счётчика, получение его значения в `LimitResponse.total_value`
     * после вызова `Commit(LimitRequest)` не должно меняться.
     *
     * Вызов этой функции является идемпотентным.
     */
    void Commit(LimitRequest request) throws (1: LimitNotFound ex1, 2: OperationNotFound ex2)

    /**
     * Отмена изменений счётчиков в операции. Взаимно исключает подтверждение
     * изменений и финализирует двухстадийный процесс.
     *
     * В отличие от подтверждающего шага, состав операции для отката всегда
     * должен быть идентичен составу операции с которой начался процесс
     * увеличения счётчиков на первом шаге. В частности должны точно совпадать
     * числа изменения значений счётчиков.
     *
     * Успешное выполнение этой функции нивелирует все изменения счётчиков в
     * этой операции.
     *
     * Вызов этой функции является идемпотентным.
     */
    void Rollback(LimitRequest request) throws (1: LimitNotFound ex1, 2: OperationNotFound ex2, 3: InvalidRequest ex3)

    /**
     * Получение значения счетчиков входящих в указанную операцию.
     *
     * Эквивалентно вызову функции `GetLastLimitsValues` с идентификаторами
     * счётчиков упомянутых внутри операции,
     * `LimitRequest.limit_changes[].limit_name`.
     */
    list<LimitResponse> Get(LimitRequest request) throws (1: LimitNotFound ex1, 2: LimitsValuesReadingException ex2)

    /**
     * Получить актуальные значения счётчиков на текущий момент.
     */
    list<LimitResponse> GetLastLimitsValues(list<LimitName> limit_names)
        throws (1: LimitNotFound ex1, 2: LimitsValuesReadingException ex2)
}
