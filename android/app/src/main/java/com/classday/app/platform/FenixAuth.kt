package com.classday.app.platform

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.browser.customtabs.CustomTabsIntent
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import com.classday.app.core.CivilCalendar
import com.classday.app.core.FenixCalendar
import com.classday.app.core.ImportedCalendar
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.security.MessageDigest
import java.security.SecureRandom
import java.time.ZoneId
import java.util.Base64

object FenixConfig {
    const val redirect = "classday://fenix"
    const val authorize = "https://fenix.tecnico.ulisboa.pt/oauth/userdialog"
    const val token = "https://fenix.tecnico.ulisboa.pt/oauth/access_token"
    const val classes = "https://fenix.tecnico.ulisboa.pt/api/fenix/v1/person/calendar/classes"
    const val evaluations = "https://fenix.tecnico.ulisboa.pt/api/fenix/v1/person/calendar/evaluations"

    fun prefs(context: Context) = try {
        val master = MasterKey.Builder(context).setKeyScheme(MasterKey.KeyScheme.AES256_GCM).build()
        EncryptedSharedPreferences.create(
            context,
            "classday.fenix",
            master,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
        )
    } catch (_: Exception) {
        context.getSharedPreferences("classday.fenix.plain", Context.MODE_PRIVATE)
    }
}

object FenixAuth {
    fun begin(context: Context, clientId: String): Boolean {
        if (clientId.isBlank()) return false
        val verifier = random(64)
        val state = random(32)
        FenixConfig.prefs(context).edit().putString("verifier", verifier).putString("state", state).putString("clientId", clientId).apply()
        val challenge = sha256Url(verifier)
        val url = Uri.parse(FenixConfig.authorize).buildUpon()
            .appendQueryParameter("client_id", clientId)
            .appendQueryParameter("redirect_uri", FenixConfig.redirect)
            .appendQueryParameter("response_type", "code")
            .appendQueryParameter("state", state)
            .appendQueryParameter("code_challenge", challenge)
            .appendQueryParameter("code_challenge_method", "S256")
            .build()
        CustomTabsIntent.Builder().build().launchUrl(context, url)
        return true
    }

    fun complete(context: Context, uri: Uri, totalWeeks: Int): ImportedCalendar? {
        val prefs = FenixConfig.prefs(context)
        val expected = prefs.getString("state", null)
        if (uri.getQueryParameter("state") != expected) return null
        val code = uri.getQueryParameter("code") ?: return null
        val verifier = prefs.getString("verifier", null) ?: return null
        val clientId = prefs.getString("clientId", "").orEmpty()
        val secret = prefs.getString("secret", "").orEmpty()
        val access = exchange(code, verifier, clientId, secret) ?: return null
        val classes = FenixCalendar.decodeClasses(get(FenixConfig.classes, access))
        val exams = FenixCalendar.decodeEvaluations(get(FenixConfig.evaluations, access))
        val calendar = CivilCalendar(ZoneId.systemDefault())
        return ImportedCalendar(
            courses = FenixCalendar.courses(classes, calendar, totalWeeks),
            exams = FenixCalendar.exams(exams, calendar),
            homework = emptyList(),
            warnings = emptyList(),
        )
    }

    private fun exchange(code: String, verifier: String, clientId: String, secret: String): String? {
        val body = listOf(
            "client_id" to clientId,
            "client_secret" to secret,
            "redirect_uri" to FenixConfig.redirect,
            "code" to code,
            "grant_type" to "authorization_code",
            "code_verifier" to verifier,
        ).joinToString("&") { "${URLEncoder.encode(it.first, "UTF-8")}=${URLEncoder.encode(it.second, "UTF-8")}" }
        val connection = URL(FenixConfig.token).openConnection() as HttpURLConnection
        connection.requestMethod = "POST"
        connection.doOutput = true
        connection.setRequestProperty("Content-Type", "application/x-www-form-urlencoded")
        connection.outputStream.use { it.write(body.toByteArray()) }
        if (connection.responseCode !in 200..299) return null
        val text = connection.inputStream.bufferedReader().readText()
        return JSONObject(text).optString("access_token").ifBlank { null }
    }

    private fun get(url: String, token: String): String {
        val connection = URL(url).openConnection() as HttpURLConnection
        connection.setRequestProperty("Authorization", "Bearer $token")
        return connection.inputStream.bufferedReader().readText()
    }

    private fun random(length: Int): String {
        val alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"
        val bytes = ByteArray(length)
        SecureRandom().nextBytes(bytes)
        return bytes.joinToString("") { alphabet[(it.toInt() and 0xff) % alphabet.length].toString() }
    }

    private fun sha256Url(verifier: String): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(verifier.toByteArray())
        return Base64.getUrlEncoder().withoutPadding().encodeToString(digest)
    }

    fun loginIntent(context: Context, clientId: String): Intent? = null
}
