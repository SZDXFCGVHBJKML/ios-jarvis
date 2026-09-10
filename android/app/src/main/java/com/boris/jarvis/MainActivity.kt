package com.boris.jarvis

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.media.MediaPlayer
import android.os.Bundle
import android.speech.RecognizerIntent
import android.util.Base64
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.Image
import androidx.compose.foundation.shape.CircleShape
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

val Bg = Color(0xFF060504)
val Acc = Color(0xFFFFB02E)
val Hot = Color(0xFFFFE6A8)
val Ink = Color(0xE0FFFFFF)
val Dim = Color(0x73FFFFFF)
val Bad = Color(0xFFFF5F3D)
val Mono = FontFamily.Monospace

data class Msg(val kind: String, val who: String, val text: String,
               val image: ByteArray? = null)

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent { JarvisApp(this) }
    }
}

fun httpJson(urlStr: String, body: JSONObject?, timeoutMs: Int = 180_000): JSONObject {
    val conn = URL(urlStr).openConnection() as HttpURLConnection
    conn.connectTimeout = 15_000
    conn.readTimeout = timeoutMs
    if (body != null) {
        conn.requestMethod = "POST"
        conn.doOutput = true
        conn.setRequestProperty("Content-Type", "application/json")
        conn.outputStream.use { it.write(body.toString().toByteArray()) }
    }
    val text = conn.inputStream.bufferedReader().readText()
    return JSONObject(text)
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun JarvisApp(activity: ComponentActivity) {
    val prefs = remember { activity.getSharedPreferences("jarvis", Context.MODE_PRIVATE) }
    var serverURL by remember {
        mutableStateOf(prefs.getString("url",
            "https://iliyazas-b650-aorus-elite-ax.tail61b14a.ts.net")!!)
    }
    var models by remember { mutableStateOf(listOf<String>()) }
    var currentModel by remember { mutableStateOf<String?>(null) }
    val msgs = remember { mutableStateListOf<Msg>() }
    var status by remember { mutableStateOf("tap the core to speak") }
    var busy by remember { mutableStateOf(false) }
    var typed by remember { mutableStateOf("") }
    var showSettings by remember { mutableStateOf(false) }
    var passwordFor by remember { mutableStateOf<String?>(null) }
    var passwordInput by remember { mutableStateOf("") }
    val modelKeys = remember { mutableStateMapOf<String, String>() }
    val scope = rememberCoroutineScope()
    val listState = rememberLazyListState()
    var player by remember { mutableStateOf<MediaPlayer?>(null) }

    fun norm(m: String?) = (m ?: "").lowercase().removeSuffix(":latest")

    fun loadModels() = scope.launch {
        try {
            val d = withContext(Dispatchers.IO) { httpJson("$serverURL/api/models", null) }
            val arr = d.getJSONArray("models")
            val list = (0 until arr.length()).map { arr.getString(it) }
            models = list
            if (currentModel == null)
                currentModel = list.firstOrNull { it.lowercase().startsWith("earl") }
                    ?: list.firstOrNull()
        } catch (_: Exception) { }
    }
    LaunchedEffect(Unit) { loadModels() }
    LaunchedEffect(msgs.size) {
        if (msgs.isNotEmpty()) listState.animateScrollToItem(msgs.size - 1)
    }

    fun playWav(b64: String) {
        try {
            val bytes = Base64.decode(b64, Base64.DEFAULT)
            val f = File(activity.cacheDir, "reply.wav")
            f.writeBytes(bytes)
            player?.release()
            player = MediaPlayer().apply {
                setDataSource(f.absolutePath)
                setOnCompletionListener { status = "tap the core to speak" }
                prepare(); start()
            }
            status = "speaking\u2026"
        } catch (_: Exception) { status = "tap the core to speak" }
    }

    val imgRe = Regex(
        "^(?:/image\\s+|(?:make|generate|create|draw|paint)\\s+(?:me\\s+)?(?:an?\\s+)?" +
        "(?:image|picture|photo|painting|art)\\s+(?:of\\s+)?)(.+)",
        setOf(RegexOption.IGNORE_CASE, RegexOption.DOT_MATCHES_ALL))

    fun send(raw: String) {
        val t = raw.trim()
        if (t.isEmpty() || busy) return
        msgs.add(Msg("you", "you", t))
        val im = imgRe.find(t)
        busy = true
        scope.launch {
            try {
                if (im != null) {
                    status = "painting\u2026 (can take a minute)"
                    val d = withContext(Dispatchers.IO) {
                        httpJson("$serverURL/api/image",
                            JSONObject().put("prompt", im.groupValues[1].trim()), 400_000)
                    }
                    if (d.has("error") && d.getString("error").isNotEmpty())
                        throw Exception(d.getString("error"))
                    val bytes = Base64.decode(d.getString("image"), Base64.DEFAULT)
                    msgs.add(Msg("image", "comfyui", "", bytes))
                    status = "tap the core to speak"
                } else {
                    status = "thinking\u2026"
                    val body = JSONObject()
                        .put("text", t).put("model", currentModel ?: "")
                        .put("voice", "earl").put("speed", 1.0)
                        .put("key", modelKeys[norm(currentModel)] ?: "")
                        .put("images", JSONArray())
                    val d = withContext(Dispatchers.IO) {
                        httpJson("$serverURL/api/chat", body)
                    }
                    if (d.has("error") && !d.isNull("error")) {
                        val err = d.getString("error")
                        if (err.lowercase().contains("locked")) {
                            passwordFor = currentModel
                            status = "tap the core to speak"
                        } else throw Exception(err)
                    } else {
                        val name = norm(currentModel).ifEmpty { "jarvis" }
                        msgs.add(Msg("jarvis", name, d.optString("reply", "")))
                        val audio = d.optString("audio", "")
                        if (audio.isNotEmpty()) playWav(audio)
                        else status = "tap the core to speak"
                    }
                }
            } catch (e: Exception) {
                msgs.add(Msg("error", "system", e.message ?: "error"))
                status = "tap the core to speak"
            }
            busy = false
        }
    }

    val speechLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.StartActivityForResult()) { res ->
        if (res.resultCode == Activity.RESULT_OK) {
            val heard = res.data
                ?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)
                ?.firstOrNull()
            if (!heard.isNullOrBlank()) send(heard)
        }
        if (status == "listening\u2026") status = "tap the core to speak"
    }
    val micPermission = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) {
            status = "listening\u2026"
            val i = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
                .putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                    RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                .putExtra(RecognizerIntent.EXTRA_PROMPT, "Speak to Jarvis")
            speechLauncher.launch(i)
        }
    }

    MaterialTheme(colorScheme = darkColorScheme(
        primary = Acc, background = Bg, surface = Bg)) {
        Column(Modifier.fillMaxSize().background(Bg)
            .padding(horizontal = 14.dp).padding(top = 34.dp, bottom = 10.dp)) {

            // header
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("J.A.R.V.I.S.", fontFamily = Mono, fontSize = 17.sp,
                    fontWeight = FontWeight.SemiBold, letterSpacing = 6.sp, color = Acc)
                Spacer(Modifier.width(10.dp))
                Box(Modifier.weight(1f).height(1.dp).background(Acc.copy(alpha = 0.35f)))
                Spacer(Modifier.width(10.dp))
                Text("\u2699", fontSize = 20.sp, color = Acc.copy(alpha = 0.7f),
                    modifier = Modifier.clickable { showSettings = true })
            }
            Spacer(Modifier.height(10.dp))

            // model chips
            Row(Modifier.horizontalScroll(rememberScrollState())) {
                models.forEach { m ->
                    val on = m == currentModel
                    Text(norm(m).uppercase(), fontFamily = Mono, fontSize = 10.sp,
                        letterSpacing = 1.2.sp,
                        color = if (on) Bg else Acc.copy(alpha = 0.7f),
                        modifier = Modifier
                            .padding(end = 7.dp)
                            .background(if (on) Acc else Color.Transparent)
                            .border(1.dp, Acc.copy(alpha = 0.35f))
                            .clickable { currentModel = m }
                            .padding(horizontal = 9.dp, vertical = 6.dp))
                }
            }
            Spacer(Modifier.height(10.dp))

            // log
            LazyColumn(Modifier.weight(1f).fillMaxWidth()
                .border(1.dp, Acc.copy(alpha = 0.2f)).padding(10.dp),
                state = listState) {
                items(msgs) { m ->
                    Column(Modifier.padding(bottom = 13.dp)) {
                        Text(m.who.uppercase(), fontFamily = Mono, fontSize = 9.sp,
                            letterSpacing = 2.5.sp,
                            color = if (m.kind == "you") Dim else Acc)
                        when (m.kind) {
                            "you" -> Text("\u203A ${m.text}", fontFamily = Mono,
                                fontSize = 13.sp, color = Dim)
                            "jarvis" -> Text(m.text, fontFamily = Mono,
                                fontSize = 13.5.sp, color = Ink,
                                modifier = Modifier.padding(start = 10.dp))
                            "error" -> Text(m.text, fontFamily = Mono,
                                fontSize = 12.sp, color = Bad)
                            "image" -> m.image?.let {
                                val bmp = BitmapFactory.decodeByteArray(it, 0, it.size)
                                if (bmp != null) Image(bmp.asImageBitmap(), "generated",
                                    Modifier.fillMaxWidth().padding(top = 4.dp)
                                        .border(1.dp, Acc.copy(alpha = 0.25f)))
                            }
                        }
                    }
                }
            }
            Spacer(Modifier.height(10.dp))

            // status + orb
            Text(status.uppercase(), fontFamily = Mono, fontSize = 10.sp,
                letterSpacing = 2.sp, color = Dim, textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth())
            Spacer(Modifier.height(8.dp))
            Box(Modifier.size(84.dp).align(Alignment.CenterHorizontally)
                .border(1.dp, Acc.copy(alpha = 0.4f), CircleShape)
                .clickable(enabled = !busy) {
                    player?.let { if (it.isPlaying) it.stop() }
                    micPermission.launch(android.Manifest.permission.RECORD_AUDIO)
                },
                contentAlignment = Alignment.Center) {
                Box(Modifier.size(if (busy) 52.dp else 42.dp)
                    .background(Hot, CircleShape))
                Box(Modifier.size(20.dp).background(Color.White, CircleShape))
            }
            Spacer(Modifier.height(10.dp))

            // input row
            Row(verticalAlignment = Alignment.CenterVertically) {
                OutlinedTextField(typed, { typed = it },
                    modifier = Modifier.weight(1f),
                    placeholder = { Text("or type here\u2026", fontFamily = Mono,
                        fontSize = 12.sp, color = Dim) },
                    textStyle = androidx.compose.ui.text.TextStyle(
                        fontFamily = Mono, fontSize = 14.sp, color = Ink),
                    singleLine = true,
                    keyboardActions = KeyboardActions(onDone = {
                        send(typed); typed = "" }),
                    colors = OutlinedTextFieldDefaults.colors(
                        focusedBorderColor = Acc,
                        unfocusedBorderColor = Acc.copy(alpha = 0.35f)))
                Spacer(Modifier.width(8.dp))
                Text("SEND", fontFamily = Mono, fontSize = 11.sp, letterSpacing = 1.5.sp,
                    color = Acc, modifier = Modifier
                        .border(1.dp, Acc.copy(alpha = 0.5f))
                        .clickable { send(typed); typed = "" }
                        .padding(horizontal = 12.dp, vertical = 12.dp))
            }
        }

        if (showSettings) {
            AlertDialog(onDismissRequest = { showSettings = false },
                containerColor = Bg,
                title = { Text("SETTINGS", fontFamily = Mono, color = Acc,
                    fontSize = 13.sp, letterSpacing = 3.sp) },
                text = {
                    OutlinedTextField(serverURL, { serverURL = it },
                        label = { Text("server url", fontFamily = Mono, color = Dim) },
                        textStyle = androidx.compose.ui.text.TextStyle(
                            fontFamily = Mono, fontSize = 12.sp, color = Ink))
                },
                confirmButton = {
                    TextButton(onClick = {
                        prefs.edit().putString("url", serverURL).apply()
                        showSettings = false
                        loadModels()
                    }) { Text("save + reload", fontFamily = Mono, color = Acc) }
                })
        }

        passwordFor?.let { m ->
            AlertDialog(onDismissRequest = { passwordFor = null; passwordInput = "" },
                containerColor = Bg,
                title = { Text("password for ${norm(m)}", fontFamily = Mono,
                    color = Acc, fontSize = 13.sp) },
                text = {
                    OutlinedTextField(passwordInput, { passwordInput = it },
                        visualTransformation = PasswordVisualTransformation(),
                        textStyle = androidx.compose.ui.text.TextStyle(
                            fontFamily = Mono, fontSize = 13.sp, color = Ink))
                },
                confirmButton = {
                    TextButton(onClick = {
                        modelKeys[norm(m)] = passwordInput
                        passwordInput = ""; passwordFor = null
                    }) { Text("unlock", fontFamily = Mono, color = Acc) }
                },
                dismissButton = {
                    TextButton(onClick = { passwordFor = null; passwordInput = "" }) {
                        Text("cancel", fontFamily = Mono, color = Dim) }
                })
        }
    }
}
