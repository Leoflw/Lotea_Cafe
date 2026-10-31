package com.loteacafe.lotea_cafe

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        crearCanalDeNotificaciones()
    }

    /**
     * Canal de las notificaciones push (mensajes y cotizaciones). Su id debe coincidir con
     * `ANDROID_CHANNEL_ID` del Worker de notificaciones y con el meta-data
     * `default_notification_channel_id` del manifiesto. Crearlo varias veces es inofensivo.
     */
    private fun crearCanalDeNotificaciones() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        val canal = NotificationChannel(
            CANAL_ID,
            "Mensajes y cotizaciones",
            NotificationManager.IMPORTANCE_DEFAULT
        )
        canal.description = "Avisos de mensajes nuevos y novedades en tus cotizaciones."
        manager.createNotificationChannel(canal)
    }

    companion object {
        const val CANAL_ID = "lotea_mensajes_cotizaciones"
    }
}
