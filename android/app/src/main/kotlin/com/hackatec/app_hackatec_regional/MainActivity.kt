package com.hackatec.app_hackatec_regional

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioManager
import android.net.Uri
import android.os.Bundle
import android.provider.CallLog
import android.telecom.TelecomManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Canal "sense_care/phone": la llamada automatica de las alertas (ver
// PhoneCallService en Dart).
class MainActivity : FlutterActivity() {
    private val pendingPermission = mutableListOf<MethodChannel.Result>()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestCallPermission" -> requestCallPermission(result)
                    "placeCall" -> result.success(placeCall(call.argument<String>("number")))
                    "isInCall" -> result.success(isInCall())
                    "wasAnswered" -> result.success(
                        wasAnswered(call.argument<Number>("since")?.toLong() ?: 0L))
                    else -> result.notImplemented()
                }
            }
    }

    private fun hasCallPermission() =
        checkSelfPermission(Manifest.permission.CALL_PHONE) == PackageManager.PERMISSION_GRANTED

    // Marcar (CALL_PHONE) y saber si contestaron (READ_CALL_LOG).
    private fun missingPermissions() = arrayOf(
        Manifest.permission.CALL_PHONE,
        Manifest.permission.READ_CALL_LOG,
    ).filter { checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }

    private fun requestCallPermission(result: MethodChannel.Result) {
        val missing = missingPermissions()
        if (missing.isEmpty()) {
            result.success(true)
            return
        }
        pendingPermission.add(result)
        // Un solo dialogo: las demas solicitudes esperan su respuesta (pedirlo
        // otra vez haria que Android cancele y todas recibieran false).
        if (pendingPermission.size == 1) {
            requestPermissions(missing.toTypedArray(), CALL_PERMISSION_REQUEST)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != CALL_PERMISSION_REQUEST) return
        val granted = hasCallPermission()
        pendingPermission.forEach { it.success(granted) }
        pendingPermission.clear()
    }

    // Marca directo (sin abrir el marcador) y en altavoz para que la voz de la
    // app se oiga en la llamada. Android solo deja al usuario marcar numeros
    // de emergencia: con esos abre el marcador.
    @SuppressLint("MissingPermission") // Se comprueba en hasCallPermission().
    private fun placeCall(number: String?): Boolean {
        if (number.isNullOrBlank() || !hasCallPermission()) return false
        val telecom = getSystemService(Context.TELECOM_SERVICE) as TelecomManager
        val extras = Bundle().apply {
            putBoolean(TelecomManager.EXTRA_START_CALL_WITH_SPEAKERPHONE, true)
        }
        return try {
            telecom.placeCall(Uri.fromParts("tel", number, null), extras)
            true
        } catch (e: SecurityException) {
            false
        }
    }

    // Si contestaron la ultima llamada saliente desde [since] (ms): el registro
    // de llamadas guarda su duracion (0 = nadie contesto). null si no se sabe
    // (sin permiso, o Android aun no la registra: lo hace al colgar).
    private fun wasAnswered(since: Long): Boolean? {
        if (checkSelfPermission(Manifest.permission.READ_CALL_LOG) !=
            PackageManager.PERMISSION_GRANTED
        ) return null
        return try {
            contentResolver.query(
                CallLog.Calls.CONTENT_URI,
                arrayOf(CallLog.Calls.DURATION),
                "${CallLog.Calls.TYPE} = ? AND ${CallLog.Calls.DATE} >= ?",
                arrayOf(CallLog.Calls.OUTGOING_TYPE.toString(), since.toString()),
                "${CallLog.Calls.DATE} DESC",
            )?.use { c -> if (c.moveToFirst()) c.getLong(0) > 0 else null }
        } catch (e: SecurityException) {
            null
        }
    }

    // Sin permisos extra: el modo de audio dice si hay una llamada activa.
    private fun isInCall(): Boolean {
        val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        return audio.mode == AudioManager.MODE_IN_CALL
    }

    companion object {
        private const val CHANNEL = "sense_care/phone"
        private const val CALL_PERMISSION_REQUEST = 4101
    }
}
