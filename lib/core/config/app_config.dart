/// Configuración de conexión al backend real de SenseCare. Se recibe por
/// entorno (`--dart-define=SENSECARE_API_URL=...`, `SENSECARE_COGNITO_CLIENT_ID`,
/// `SENSECARE_AWS_REGION`); los valores por defecto son los de la demo.
///
/// Valores tomados de la pestaña "Outputs" de CloudFormation tras
/// `cdk deploy` de `SenseCareDemoStack`. Ver `docs/DEMO_INGEST_AUTH.md` en
/// el repo del backend para el contrato HTTP completo (login,
/// emparejamiento, lectura de telemetría).
class AppConfig {
  const AppConfig._();

  /// Región de AWS donde vive el User Pool de Cognito.
  static const String awsRegion =
      String.fromEnvironment('SENSECARE_AWS_REGION', defaultValue: 'us-east-1');

  /// Cliente (sin secreto) del User Pool de Cognito usado por la app.
  /// Output `DemoUserPoolClientId`.
  static const String cognitoUserPoolClientId = String.fromEnvironment(
      'SENSECARE_COGNITO_CLIENT_ID',
      defaultValue: '5vt4bd7gemjnji9mjqsanq2qbo');

  /// URL base del API de ingesta/consulta (sin slash final).
  /// Output `DemoIngestApiUrl`.
  static const String apiBaseUrl = String.fromEnvironment('SENSECARE_API_URL',
      defaultValue: 'https://an1kxgw9wj.execute-api.us-east-1.amazonaws.com');

  /// Endpoint de Cognito InitiateAuth para esta región.
  static String get cognitoIdpEndpoint => 'https://cognito-idp.$awsRegion.amazonaws.com/';
}
