/// Resultado de `POST /cases/{caseId}/cancel` o `/escalate`.
///
/// Diseño: un `409` (alguien más ya decidió el caso -- un segundo intento
/// desde esta misma app, el `VOICE_CHECKIN` de la Pi, u otro cuidador) NO
/// se modela como una excepción más de la familia `ApiException`
/// (`sensecare_api_service.dart`). Ahí las excepciones tipadas
/// (`ForbiddenException`, `NotFoundException`, etc.) representan errores
/// reales -- algo que impidió completar la solicitud. Un 409 aquí no es
/// eso: es una respuesta 2xx-equivalente en espíritu ("tu decisión no se
/// aplicó porque ya había una firme"), perfectamente esperable, que la UI
/// debe poder mostrar sin un `catch` genérico de error. Por eso se modela
/// como un resultado tipado con [conflict] en vez de lanzar.
///
/// [alertStatus] siempre trae el estado REAL vigente en el backend (el que
/// el usuario pidió si tuvo éxito, o el que ya estaba si hubo conflicto),
/// para que quien llama nunca tenga que aplicar optimistamente lo que se
/// pidió -- ver `AlertsProvider._applyDecision`.
class CaseDecisionResult {
  final String caseId;
  final String alertStatus;

  /// `true` sólo si el backend respondió 409 (la decisión de esta llamada
  /// no se aplicó porque el caso ya estaba resuelto por otra vía).
  final bool conflict;

  /// Mensaje del backend en el 409 (p. ej. "case already escalated").
  /// `null` en una respuesta 200 normal.
  final String? error;

  const CaseDecisionResult({
    required this.caseId,
    required this.alertStatus,
    this.conflict = false,
    this.error,
  });

  factory CaseDecisionResult.fromJson(
    Map<String, dynamic> j, {
    bool conflict = false,
  }) =>
      CaseDecisionResult(
        caseId: j['caseId'] as String? ?? '',
        alertStatus: j['alertStatus'] as String? ?? '',
        conflict: conflict,
        error: j['error'] as String?,
      );
}
