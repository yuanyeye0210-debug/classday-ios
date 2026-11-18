package com.classday.app.ui

import android.Manifest
import android.content.Intent
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGesturesAfterLongPress
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Snackbar
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.Surface
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.zIndex
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInParent
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.classday.app.core.StoreCodec
import com.classday.app.core.CivilStamp
import com.classday.app.core.ClassdayThemes
import com.classday.app.core.CountdownCopy
import com.classday.app.core.Course
import com.classday.app.core.CourseReminder
import com.classday.app.core.ExamCopy
import com.classday.app.core.ExamTimeline
import com.classday.app.core.ClassCancellation
import com.classday.app.core.CourseDraft
import com.classday.app.core.ScheduleTextImporter
import com.classday.app.core.WeekDaySelection
import com.classday.app.core.HolidayImporter
import com.classday.app.core.HolidayPeriod
import com.classday.app.core.ICSImporter
import com.classday.app.core.Meeting
import com.classday.app.core.Occurrence
import com.classday.app.core.PerformanceTier
import com.classday.app.core.ScheduleCopy
import com.classday.app.core.ScheduleEngine
import com.classday.app.core.ShareCodec
import com.classday.app.core.WeekParity
import com.classday.app.core.gradeConflict
import com.classday.app.core.newId
import com.classday.app.platform.CalendarSync
import com.classday.app.platform.Maps
import com.classday.app.platform.OcrReader
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.net.URL
import java.time.Instant
import java.time.LocalDate
import kotlin.math.cos
import kotlin.math.roundToInt
import kotlin.math.sin

@Composable
fun rememberTilt(enabled: Boolean): Offset {
    val context = LocalContext.current
    var offset by remember { mutableStateOf(Offset.Zero) }
    DisposableEffect(enabled) {
        if (!enabled) {
            offset = Offset.Zero
            onDispose { }
        } else {
            val manager = context.getSystemService(SensorManager::class.java)
            val sensor = manager?.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
            if (manager == null || sensor == null) {
                onDispose { }
            } else {
                val handler = Handler(Looper.getMainLooper())
                var sx = 0f
                var sy = 0f
                val listener = object : SensorEventListener {
                    override fun onSensorChanged(event: SensorEvent) {
                        sx = sx * 0.86f + event.values[0] * 0.14f
                        sy = sy * 0.86f + event.values[1] * 0.14f
                        val next = Offset((-sx * 2.4f).coerceIn(-18f, 18f), (sy * 2.2f).coerceIn(-18f, 18f))
                        handler.post { offset = next }
                    }
                    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit
                }
                manager.registerListener(listener, sensor, SensorManager.SENSOR_DELAY_GAME)
                onDispose { manager.unregisterListener(listener) }
            }
        }
    }
    return offset
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ClassdayApp(model: ClassdayModel) {
    var nowMillis by remember { mutableStateOf(System.currentTimeMillis()) }
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    LaunchedEffect(lifecycle) {
        lifecycle.repeatOnLifecycle(Lifecycle.State.RESUMED) {
            while (true) {
                nowMillis = System.currentTimeMillis()
                kotlinx.coroutines.delay(5_000)
            }
        }
    }
    BackHandler(enabled = model.canGoBack()) { model.back() }
    val classroom = com.classday.app.core.TodayProjection.make(Instant.ofEpochMilli(nowMillis),
        model.document, model.calendar, model.loadError == null).classroomCourse != null
    val theme = model.theme
    val palette = rememberIosPalette()
    val motion = !classroom && model.tier != PerformanceTier.saver && theme.usesMotion
    val tilt = rememberTilt(motion)
    val scheme = if (palette.isDark) {
        androidx.compose.material3.darkColorScheme(
            primary = palette.accent,
            onPrimary = Color.White,
            background = Color.Transparent,
            surface = palette.card,
            onBackground = palette.ink,
            onSurface = palette.ink,
            secondary = palette.accentInk,
            outline = palette.line,
        )
    } else {
        androidx.compose.material3.lightColorScheme(
            primary = palette.accent,
            onPrimary = Color.White,
            background = Color.Transparent,
            surface = palette.card,
            onBackground = palette.ink,
            onSurface = palette.ink,
            secondary = palette.accentInk,
            outline = palette.line,
        )
    }
    MaterialTheme(colorScheme = scheme) {
      androidx.compose.runtime.CompositionLocalProvider(LocalClassdayTheme provides theme) {
        Box(Modifier.fillMaxSize()) {
            ThemeBackdrop(theme, if (classroom) PerformanceTier.saver else model.tier, tilt)
            Scaffold(
                containerColor = Color.Transparent,
                bottomBar = {
                    if (model.screen is Screen.Today || model.screen is Screen.Week || model.screen is Screen.Countdown || model.screen is Screen.Settings) {
                        FloatingCapsuleTabBar(
                            current = model.screen,
                            onSelect = { model.goHome(it) },
                            tier = model.tier,
                        )
                    }
                },
            ) { padding ->
                Box(Modifier.padding(top = padding.calculateTopPadding()).fillMaxSize()) {
                    when (val screen = model.screen) {
                        Screen.Today -> TodayPage(model, nowMillis)
                        Screen.Week -> WeekPage(model, tilt)
                        Screen.Countdown -> CountdownPage(model, nowMillis)
                        Screen.Settings -> SettingsHome(model)
                        Screen.Appearance -> AppearancePage(model)
                        Screen.Periods -> PeriodsPage(model)
                        Screen.SemesterEdit -> SemesterPage(model)
                        Screen.Holidays -> HolidayPage(model)
                        Screen.Reminders -> ReminderPage(model)
                        Screen.DataPage -> DataPage(model)
                        Screen.RoomLocations -> RoomLocationsPage(model)
                        Screen.About -> AboutPage(model)
                        Screen.StudyGrades -> StudyGradesPage(model)
                        is Screen.GradePrediction -> GradePredictionPage(model, screen.courseId)
                        Screen.ImportReview -> ImportReviewPage(model)
                        Screen.Merge -> MergePage(model)
                        is Screen.Detail -> DetailPage(model, screen)
                        is Screen.Editor -> EditorPage(model, screen.courseId)
                    }
                }
            }
            model.detailSheet?.let { detail ->
                CourseDetailBottomSheet(
                    model = model,
                    screen = detail,
                    nowMillis = nowMillis,
                    onDismiss = { model.dismissDetailSheet() },
                )
            }
            model.banner?.let { text ->
                Snackbar(
                    modifier = Modifier.align(Alignment.BottomCenter).padding(16.dp).padding(bottom = 72.dp),
                    action = {
                        if (text.contains("撤销")) TextButton(onClick = { model.undo() }) { Text("撤销") }
                        TextButton(onClick = { model.banner = null }) { Text("知道了") }
                    },
                ) { Text(text) }
            }
        }
    }
}
      }

@Composable
private fun PageTitle(title: String, onBack: (() -> Unit)?) {
    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 4.dp)) {
        if (onBack != null) {
            IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "返回") }
        }
        Text(title, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
    }
}

@Composable
private fun TodayPage(model: ClassdayModel, nowMillis: Long) {
    val palette = rememberIosPalette()
    val context = LocalContext.current
    val now = Instant.ofEpochMilli(nowMillis)
    val zonedNow = now.atZone(model.calendar.zone)
    val localDate = zonedNow.toLocalDate()
    val document = model.document
    val overview = com.classday.app.core.TodayProjection.make(now, document, model.calendar, model.loadError == null)
    val classroom = overview.classroomCourse
    var showAllDuringClass by remember(classroom?.id) { mutableStateOf(false) }
    val today = overview.displayedCourses(showAllDuringClass)
    val next = overview.focus
    val currentWeek = model.calendar.weekIndex(localDate, document.semester) ?: 1
    val holiday = model.calendar.holiday(zonedNow, document.semester)

    var showPlusMenu by remember { mutableStateOf(false) }
    var showNewEventDialog by remember { mutableStateOf(false) }
    var eventTitle by remember { mutableStateOf("") }
    var eventNote by remember { mutableStateOf("") }
    var eventStart by remember { mutableStateOf("%04d-%02d-%02dT19:00".format(localDate.year, localDate.monthValue, localDate.dayOfMonth)) }
    var eventEnd by remember { mutableStateOf("%04d-%02d-%02dT20:30".format(localDate.year, localDate.monthValue, localDate.dayOfMonth)) }

    if (showNewEventDialog) {
        AlertDialog(
            onDismissRequest = { showNewEventDialog = false },
            title = { Text("新建日程", fontWeight = FontWeight.Bold) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Field("日程标题", eventTitle) { eventTitle = it }
                    Field("地点或备注（可空）", eventNote) { eventNote = it }
                    Field("开始 yyyy-MM-ddTHH:mm", eventStart) { eventStart = it }
                    Field("结束 yyyy-MM-ddTHH:mm", eventEnd) { eventEnd = it }
                }
            },
            confirmButton = {
                TextButton(onClick = {
                    if (model.savePersonalEvent(eventTitle, eventNote, eventStart, eventEnd)) {
                        eventTitle = ""
                        eventNote = ""
                        showNewEventDialog = false
                    }
                }) { Text("保存日程", fontWeight = FontWeight.Bold) }
            },
            dismissButton = {
                TextButton(onClick = { showNewEventDialog = false }) { Text("取消") }
            },
        )
    }

    val weekdayLong = when (localDate.dayOfWeek.value) {
        1 -> "星期一"
        2 -> "星期二"
        3 -> "星期三"
        4 -> "星期四"
        5 -> "星期五"
        6 -> "星期六"
        else -> "星期日"
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 16.dp)
            .padding(top = 8.dp, bottom = 110.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        // Header: Date + Semester/Week/Demo chip + Top-Right '+' Button
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.Top,
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = "${localDate.monthValue}月${localDate.dayOfMonth}日 · $weekdayLong",
                    color = palette.ink,
                    fontSize = 27.sp,
                    fontWeight = FontWeight.Black,
                    letterSpacing = (-0.5).sp,
                )
                Row(
                    modifier = Modifier.padding(top = 4.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    Text(
                        text = "${document.semester.shortName} · 第 $currentWeek 周",
                        color = palette.secondary,
                        fontSize = 13.sp,
                        fontWeight = FontWeight.SemiBold,
                    )
                    if (document.origin == com.classday.app.core.DataOrigin.demo) {
                        StatusPill(
                            text = "演示数据",
                            containerColor = palette.hero,
                            contentColor = palette.accentInk,
                        )
                    }
                    if (holiday != null) {
                        StatusPill(
                            text = "假期 · ${holiday.name}",
                            containerColor = palette.courseBg("orange"),
                            contentColor = palette.courseInk("orange"),
                        )
                    }
                }
            }
            Box {
                CircleActionBtn(
                    label = "+",
                    size = 40.dp,
                    fontSize = 22.sp,
                    contentDescription = "新建或导入",
                    onClick = { showPlusMenu = true },
                )
                androidx.compose.material3.DropdownMenu(
                    expanded = showPlusMenu,
                    onDismissRequest = { showPlusMenu = false },
                ) {
                    androidx.compose.material3.DropdownMenuItem(
                        text = { Text("新建课程", fontWeight = FontWeight.SemiBold) },
                        onClick = {
                            showPlusMenu = false
                            model.open(Screen.Editor(null))
                        },
                    )
                    androidx.compose.material3.DropdownMenuItem(
                        text = { Text("新建日程", fontWeight = FontWeight.SemiBold) },
                        onClick = {
                            showPlusMenu = false
                            showNewEventDialog = true
                        },
                    )
                    androidx.compose.material3.DropdownMenuItem(
                        text = { Text("导入数据", fontWeight = FontWeight.SemiBold) },
                        onClick = {
                            showPlusMenu = false
                            model.open(Screen.DataPage)
                        },
                    )
                }
            }
        }

        if (model.loadError != null) {
            FrostedCard(tier = model.tier) {
                Text("读不到课表，请到我的 → 数据检查或恢复课表。", color = palette.secondary, fontSize = 14.sp)
            }
        } else {
            // Next / Ongoing Class Hero Card
            val heroShape = RoundedCornerShape(26.dp)
            if (next == null) {
                FrostedCard(
                    modifier = Modifier.fillMaxWidth(),
                    cornerRadius = 26.dp,
                    tier = model.tier,
                ) {
                    StatusPill(
                        text = "下一节课",
                        containerColor = palette.hero,
                        contentColor = palette.accentInk,
                    )
                    Spacer(Modifier.height(8.dp))
                    Text("暂无后续课程", color = palette.ink, fontSize = 20.sp, fontWeight = FontWeight.Black)
                    Text("近期没有待上的课程安排，好好休息", color = palette.secondary, fontSize = 13.sp, modifier = Modifier.padding(top = 4.dp))
                }
            } else {
                val cBg = palette.courseBg(next.colorID)
                val cBgEnd = if (palette.isDark) palette.courseBg(next.colorID, alpha = 0.65f) else Color.White.copy(alpha = 0.90f)
                val cInk = palette.courseInk(next.colorID)
                val startClock = next.timeText.substringBefore("–").trim()
                val nextDate = Instant.ofEpochMilli(next.startEpochMillis).atZone(model.calendar.zone).toLocalDate()
                val countdownLabel = if (overview.inProgress) {
                    "还剩 ${CountdownCopy.remaining(next.endEpochMillis, nowMillis)}"
                } else {
                    val rem = CountdownCopy.remaining(next.startEpochMillis, nowMillis)
                    if (nextDate == localDate) "${rem}后 · $startClock"
                    else "${ScheduleCopy.weekdayName(next.weekday)} · $startClock"
                }

                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .journalPress { model.open(Screen.Detail(next.courseID, next.meetingID, next.weekIndex)) }
                        .clip(heroShape)
                        .background(
                            brush = androidx.compose.ui.graphics.Brush.linearGradient(
                                colors = listOf(cBg, cBgEnd),
                                start = Offset.Zero,
                                end = Offset(900f, 600f),
                            ),
                            shape = heroShape,
                        )
                        .border(1.dp, palette.frostedBorder, heroShape)
                        .padding(18.dp),
                ) {
                    // Subtle white radial glow in top-right corner
                    Canvas(modifier = Modifier.size(110.dp).align(Alignment.TopEnd).offset(x = 24.dp, y = (-24).dp)) {
                        drawCircle(
                            brush = androidx.compose.ui.graphics.Brush.radialGradient(
                                colors = listOf(Color.White.copy(alpha = if (palette.isDark) 0.14f else 0.65f), Color.Transparent),
                            ),
                        )
                    }

                    Column(modifier = Modifier.fillMaxWidth()) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            StatusPill(
                                text = if (overview.inProgress) "正在上课" else "下一节课",
                                containerColor = if (palette.isDark) Color.White.copy(alpha = 0.14f) else Color.White.copy(alpha = 0.76f),
                                contentColor = cInk,
                            )
                            Text(
                                text = countdownLabel,
                                color = cInk,
                                fontSize = 12.5.sp,
                                fontWeight = FontWeight.Bold,
                            )
                        }

                        Row(
                            modifier = Modifier.fillMaxWidth().padding(top = 12.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(14.dp),
                        ) {
                            CourseGlyphTile(
                                name = next.name,
                                colorID = next.colorID,
                                size = 58.dp,
                                cornerRadius = 18.dp,
                                fontSize = 26.sp,
                                frostedHero = true,
                            )
                            Column(modifier = Modifier.weight(1f)) {
                                Text(
                                    text = next.name,
                                    color = palette.ink,
                                    fontSize = 21.sp,
                                    fontWeight = FontWeight.Black,
                                    maxLines = 1,
                                )
                                Text(
                                    text = "${next.location.ifBlank { "未设教室" }} · 第 ${next.startPeriod}–${next.endPeriod} 节",
                                    color = palette.ink.copy(alpha = 0.72f),
                                    fontSize = 13.sp,
                                    fontWeight = FontWeight.SemiBold,
                                    modifier = Modifier.padding(top = 3.dp),
                                )
                            }
                            Text(
                                text = startClock,
                                color = cInk,
                                fontSize = 30.sp,
                                fontWeight = FontWeight.Black,
                                letterSpacing = (-1).sp,
                            )
                        }

                        Row(
                            modifier = Modifier.fillMaxWidth().padding(top = 14.dp),
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            val btnShape = RoundedCornerShape(14.dp)
                            val btnBg = if (palette.isDark) Color.White.copy(alpha = 0.12f) else Color.White.copy(alpha = 0.78f)
                            Box(
                                modifier = Modifier
                                    .weight(1f)
                                    .height(40.dp)
                                    .journalPress {
                                        val pin = document.rooms.firstOrNull { it.name == next.location }
                                        Maps.open(context, next.location, pin) { model.banner = it }
                                    }
                                    .clip(btnShape)
                                    .background(btnBg, btnShape)
                                    .border(1.dp, Color.White.copy(alpha = if (palette.isDark) 0.16f else 0.9f), btnShape),
                                contentAlignment = Alignment.Center,
                            ) {
                                Text("📍 导航到教室", color = palette.ink, fontSize = 13.sp, fontWeight = FontWeight.Bold)
                            }
                            Box(
                                modifier = Modifier
                                    .weight(1f)
                                    .height(40.dp)
                                    .journalPress {
                                        if (classroom != null) {
                                            showAllDuringClass = !showAllDuringClass
                                        } else {
                                            model.ensureReminderDraft()
                                            model.open(Screen.Reminders)
                                        }
                                    }
                                    .clip(btnShape)
                                    .background(btnBg, btnShape)
                                    .border(1.dp, Color.White.copy(alpha = if (palette.isDark) 0.16f else 0.9f), btnShape),
                                contentAlignment = Alignment.Center,
                            ) {
                                Text("🔕 上课专注", color = palette.ink, fontSize = 13.sp, fontWeight = FontWeight.Bold)
                            }
                        }
                    }
                }
            }

            if (classroom != null) {
                FrostedCard(tier = model.tier, cornerRadius = 18.dp, contentPadding = androidx.compose.foundation.layout.PaddingValues(12.dp)) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Column(modifier = Modifier.weight(1f)) {
                            Text("应用内上课专注 · 自动生效", color = palette.ink, fontWeight = FontWeight.Bold, fontSize = 13.sp)
                            Text("突出当前课，减少背景动效，下课恢复。不会切换系统勿扰或静音其他 App。", color = palette.secondary, fontSize = 11.5.sp)
                        }
                        TextButton(onClick = { showAllDuringClass = !showAllDuringClass }) {
                            Text(if (showAllDuringClass) "只看当前课" else "查看今天全部课程", fontWeight = FontWeight.Bold)
                        }
                    }
                }
            }

            // Progress Ring Card
            val allTodayCourses = overview.courses
            val donePeriods = allTodayCourses.filter { it.endEpochMillis <= nowMillis }
                .sumOf { (it.endPeriod - it.startPeriod + 1).coerceAtLeast(1) }
            val totalPeriods = allTodayCourses.sumOf { (it.endPeriod - it.startPeriod + 1).coerceAtLeast(1) }
            val remPeriods = (totalPeriods - donePeriods).coerceAtLeast(0)
            val progressFraction = if (totalPeriods == 0) 1f else (donePeriods.toFloat() / totalPeriods.toFloat()).coerceIn(0f, 1f)

            FrostedCard(
                modifier = Modifier.fillMaxWidth(),
                cornerRadius = 18.dp,
                tier = model.tier,
                contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 14.dp, vertical = 11.dp),
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Box(modifier = Modifier.size(34.dp), contentAlignment = Alignment.Center) {
                        Canvas(modifier = Modifier.fillMaxSize()) {
                            val strokeW = 3.5.dp.toPx()
                            drawCircle(
                                color = palette.line,
                                style = androidx.compose.ui.graphics.drawscope.Stroke(width = strokeW),
                            )
                            drawArc(
                                color = palette.accent,
                                startAngle = -90f,
                                sweepAngle = 360f * progressFraction.coerceAtLeast(if (totalPeriods > 0) 0.12f else 1f),
                                useCenter = false,
                                style = androidx.compose.ui.graphics.drawscope.Stroke(
                                    width = strokeW,
                                    cap = androidx.compose.ui.graphics.StrokeCap.Round,
                                ),
                            )
                        }
                        Text("✓", color = palette.accent, fontSize = 11.sp, fontWeight = FontWeight.Black)
                    }
                    Text(
                        text = if (totalPeriods > 0) {
                            "今天已上 $donePeriods 节 · 还剩 $remPeriods 节"
                        } else {
                            "今天没有课程 · 已完成今日安排"
                        },
                        color = palette.ink,
                        fontSize = 13.5.sp,
                        fontWeight = FontWeight.Bold,
                    )
                }
            }

            // Today's Courses Timeline Section
            Row(
                modifier = Modifier.fillMaxWidth().padding(top = 2.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text("今天课程", color = palette.ink, fontSize = 15.sp, fontWeight = FontWeight.Bold)
                if (today.isNotEmpty()) {
                    Text("${today.size} 门课", color = palette.secondary, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
                }
            }

            if (today.isEmpty()) {
                FrostedCard(
                    modifier = Modifier.fillMaxWidth(),
                    cornerRadius = 18.dp,
                    tier = model.tier,
                ) {
                    Text("今天没有课程", color = palette.secondary, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
                }
            }

            // Show today's courses; if today has none and next class exists on an upcoming day, also show that upcoming day's preview timeline
            val previewItems = if (today.isNotEmpty()) {
                today
            } else if (next != null) {
                ScheduleEngine.occurrences(next.weekIndex, document.courses, document.semester, model.calendar, document.scheduleContext)
                    .filter { it.weekday == next.weekday }
                    .sortedBy { it.startPeriod }
            } else {
                emptyList()
            }

            if (today.isEmpty() && previewItems.isNotEmpty() && next != null) {
                Text(
                    text = "${ScheduleCopy.weekdayName(next.weekday)}课程预览",
                    color = palette.secondary,
                    fontSize = 13.sp,
                    fontWeight = FontWeight.Bold,
                )
            }

            previewItems.forEach { item ->
                val isPast = today.isNotEmpty() && item.endEpochMillis <= nowMillis
                val isFocus = next?.id == item.id
                val times = item.timeText.split("–")
                val startText = times.getOrNull(0)?.trim().orEmpty()
                val endText = times.getOrNull(1)?.trim().orEmpty()
                val cInk = palette.courseInk(item.colorID)
                val cBg = palette.courseBg(item.colorID)

                FrostedCard(
                    modifier = Modifier.fillMaxWidth(),
                    cornerRadius = 18.dp,
                    tier = model.tier,
                    borderColor = if (isFocus) cInk.copy(alpha = 0.45f) else null,
                    borderWidth = if (isFocus) 1.5.dp else 1.dp,
                    contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 14.dp, vertical = 12.dp),
                    onClick = { model.open(Screen.Detail(item.courseID, item.meetingID, item.weekIndex)) },
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        Column(
                            modifier = Modifier.width(46.dp),
                            horizontalAlignment = Alignment.End,
                        ) {
                            Text(
                                text = startText,
                                color = if (isPast) palette.secondary else palette.ink,
                                fontSize = 13.sp,
                                fontWeight = FontWeight.Black,
                            )
                            Text(
                                text = endText,
                                color = palette.secondary,
                                fontSize = 11.sp,
                                fontWeight = FontWeight.SemiBold,
                            )
                        }
                        Box(
                            modifier = Modifier
                                .width(5.dp)
                                .height(38.dp)
                                .clip(RoundedCornerShape(3.dp))
                                .background(
                                    if (isPast) palette.line else cInk.copy(alpha = 0.75f),
                                    RoundedCornerShape(3.dp),
                                ),
                        )
                        Column(modifier = Modifier.weight(1f)) {
                            Text(
                                text = item.name,
                                color = if (isPast) palette.secondary else palette.ink,
                                fontSize = 15.5.sp,
                                fontWeight = FontWeight.Black,
                            )
                            Text(
                                text = "${item.location.ifBlank { "未设教室" }} · 第 ${item.startPeriod}–${item.endPeriod} 节",
                                color = palette.secondary,
                                fontSize = 12.sp,
                                modifier = Modifier.padding(top = 2.dp),
                            )
                        }
                        when {
                            isPast -> {
                                Column(horizontalAlignment = Alignment.End) {
                                    Box(
                                        modifier = Modifier
                                            .size(24.dp)
                                            .clip(androidx.compose.foundation.shape.CircleShape)
                                            .background(palette.elevated, androidx.compose.foundation.shape.CircleShape),
                                        contentAlignment = Alignment.Center,
                                    ) {
                                        Text("✓", color = palette.secondary, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                                    }
                                    Text("已结束", color = palette.secondary, fontSize = 10.sp)
                                }
                            }
                            isFocus -> {
                                StatusPill(
                                    text = if (overview.inProgress) "进行中" else "下一节",
                                    containerColor = cBg,
                                    contentColor = cInk,
                                )
                            }
                        }
                    }
                }
            }

            // Personal Events (if any)
            if (document.personalEvents.isNotEmpty()) {
                document.personalEvents.take(3).forEach { ev ->
                    FrostedCard(
                        modifier = Modifier.fillMaxWidth(),
                        cornerRadius = 18.dp,
                        tier = model.tier,
                        contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 14.dp, vertical = 10.dp),
                    ) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.SpaceBetween,
                        ) {
                            Column(modifier = Modifier.weight(1f)) {
                                Text(ev.title, color = palette.ink, fontSize = 14.5.sp, fontWeight = FontWeight.Bold)
                                Text(
                                    text = "${ev.startISO.replace('T', ' ')} · ${ev.note.ifBlank { "个人日程" }}",
                                    color = palette.secondary,
                                    fontSize = 12.sp,
                                )
                            }
                            TextButton(onClick = { model.deletePersonalEvent(ev.id) }) {
                                Text("删除", color = palette.secondary, fontSize = 12.sp)
                            }
                        }
                    }
                }
            }

            // Exams & Homework Dual Cards Section
            val examBuckets = ExamTimeline.classify(document.exams, nowMillis) {
                CivilStamp.instant(it, model.calendar)?.toEpochMilli()
            }
            val nearestExam = examBuckets.focus
            val pendingHomework = document.homework.filter { !it.done }.sortedBy { it.dueISO }

            if (nearestExam != null || document.homework.isNotEmpty()) {
                Text(
                    text = "考试与作业",
                    color = palette.ink,
                    fontSize = 15.sp,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier.padding(top = 4.dp),
                )

                if (nearestExam != null) {
                    val examInstant = CivilStamp.instant(nearestExam.startISO, model.calendar)
                    // focus 只会是进行中或未开始的考试；进行中时 examDays 为 null，显示「考试中」。
                    val examDays = ExamTimeline.daysUntilStart(examInstant?.toEpochMilli(), nowMillis)
                    val examIsOngoing = nearestExam in examBuckets.ongoing
                    val examZoned = examInstant?.atZone(model.calendar.zone)
                    val examDateText = if (examZoned != null) {
                        "${examZoned.monthValue}月${examZoned.dayOfMonth}日 ${ScheduleCopy.weekdayName(examZoned.dayOfWeek.value)} %02d:%02d".format(examZoned.hour, examZoned.minute)
                    } else {
                        nearestExam.startISO
                    }
                    val orangeBg = palette.courseBg("orange")
                    val orangeInk = palette.courseInk("orange")
                    val examShape = RoundedCornerShape(22.dp)

                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .journalPress { model.goHome(Screen.Countdown) }
                            .clip(examShape)
                            .background(
                                brush = androidx.compose.ui.graphics.Brush.linearGradient(
                                    colors = listOf(
                                        orangeBg,
                                        if (palette.isDark) orangeBg.copy(alpha = 0.7f) else Color(0xFFFFF4EB),
                                    ),
                                ),
                                shape = examShape,
                            )
                            .border(1.dp, palette.frostedBorder, examShape)
                            .padding(15.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Column(modifier = Modifier.weight(1f)) {
                            StatusPill(
                                text = if (examIsOngoing) "正在考试" else "考试倒计时",
                                containerColor = if (palette.isDark) Color.White.copy(alpha = 0.14f) else Color.White.copy(alpha = 0.75f),
                                contentColor = orangeInk,
                            )
                            Text(
                                text = nearestExam.courseName,
                                color = palette.ink,
                                fontSize = 17.sp,
                                fontWeight = FontWeight.Black,
                                modifier = Modifier.padding(top = 6.dp),
                            )
                            Text(
                                text = "$examDateText · ${nearestExam.location.ifBlank { "考场待定" }}",
                                color = palette.ink.copy(alpha = 0.68f),
                                fontSize = 12.sp,
                                modifier = Modifier.padding(top = 2.dp),
                            )
                        }
                        Column(horizontalAlignment = Alignment.End) {
                            Text(
                                text = examDays?.toString() ?: if (examIsOngoing) "考试中" else "—",
                                color = orangeInk,
                                fontSize = if (examDays != null) 34.sp else 20.sp,
                                fontWeight = FontWeight.Black,
                                letterSpacing = (-1).sp,
                            )
                            Text(
                                text = when {
                                    examDays != null -> "天后开考"
                                    examIsOngoing -> "祝顺利"
                                    else -> "时间待定"
                                },
                                color = orangeInk,
                                fontSize = 11.sp,
                                fontWeight = FontWeight.Bold,
                            )
                        }
                    }
                }

                if (document.homework.isNotEmpty()) {
                    FrostedCard(
                        modifier = Modifier.fillMaxWidth(),
                        cornerRadius = 18.dp,
                        tier = model.tier,
                        contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 14.dp, vertical = 12.dp),
                    ) {
                        Row(
                            modifier = Modifier.fillMaxWidth().padding(bottom = 8.dp),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Text("待办作业", color = palette.secondary, fontSize = 12.5.sp, fontWeight = FontWeight.Bold)
                            Text(
                                text = "全部 ›",
                                color = palette.accent,
                                fontSize = 12.5.sp,
                                fontWeight = FontWeight.Bold,
                                modifier = Modifier.journalPress { model.goHome(Screen.Countdown) },
                            )
                        }
                        val shownTasks = if (pendingHomework.isNotEmpty()) pendingHomework.take(4) else document.homework.take(2)
                        shownTasks.forEachIndexed { idx, task ->
                            val dueInstant = CivilStamp.instant(task.dueISO, model.calendar)
                            val dueDate = dueInstant?.atZone(model.calendar.zone)?.toLocalDate()
                            val dayDiff = if (dueDate != null) java.time.temporal.ChronoUnit.DAYS.between(localDate, dueDate) else 0L
                            val (dueLabel, isUrgent) = when {
                                task.done -> "已完成" to false
                                dayDiff < 0 -> "已逾期" to true
                                dayDiff == 0L -> "今天截止" to true
                                dayDiff == 1L -> "明天截止" to true
                                else -> "${dayDiff}天后" to false
                            }
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(vertical = 6.dp),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(10.dp),
                            ) {
                                Box(
                                    modifier = Modifier
                                        .size(20.dp)
                                        .journalPress { model.toggleHomework(task.id) }
                                        .clip(androidx.compose.foundation.shape.CircleShape)
                                        .background(
                                            if (task.done) palette.accent else Color.Transparent,
                                            androidx.compose.foundation.shape.CircleShape,
                                        )
                                        .border(
                                            2.dp,
                                            palette.accent,
                                            androidx.compose.foundation.shape.CircleShape,
                                        ),
                                    contentAlignment = Alignment.Center,
                                ) {
                                    if (task.done) {
                                        Text("✓", color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Black)
                                    }
                                }
                                Text(
                                    text = if (task.courseName.isNotBlank()) "${task.courseName} · ${task.title}" else task.title,
                                    color = if (task.done) palette.secondary else palette.ink,
                                    fontSize = 14.sp,
                                    fontWeight = FontWeight.Bold,
                                    modifier = Modifier.weight(1f),
                                )
                                StatusPill(
                                    text = dueLabel,
                                    containerColor = if (isUrgent) palette.courseBg("orange") else palette.hero,
                                    contentColor = if (isUrgent) palette.courseInk("orange") else palette.accentInk,
                                )
                            }
                            if (idx < shownTasks.lastIndex) {
                                Box(Modifier.fillMaxWidth().height(1.dp).background(palette.line.copy(alpha = 0.6f)))
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun WeekPage(model: ClassdayModel, tilt: Offset) {
    val palette = rememberIosPalette()
    val week = model.weekIndex()
    val items = model.occurrences()
    val now = System.currentTimeMillis()
    val next = ScheduleEngine.next(Instant.ofEpochMilli(now), model.document.courses, model.document.semester, model.calendar, model.document.scheduleContext)
    val current = ScheduleEngine.current(Instant.ofEpochMilli(now), model.document.courses, model.document.semester, model.calendar, model.document.scheduleContext)
    val focus = current ?: next
    val todayDate = LocalDate.now(model.calendar.zone)
    val todayWeek = model.calendar.weekIndex(todayDate, model.document.semester) ?: 1
    val todayWeekday = todayDate.dayOfWeek.value
    val weekDates = model.calendar.datesInWeek(week, model.document.semester)
    var modeIndex by rememberSaveable { mutableIntStateOf(0) }
    var selectedWeekday by remember(week) {
        mutableIntStateOf(WeekDaySelection.initial(week, todayWeek, todayWeekday))
    }
    val swipeThresholdPx = with(LocalDensity.current) { 70.dp.toPx() }
    var horizontalDrag by remember(week) { mutableStateOf(0f) }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .pointerInput(week, swipeThresholdPx) {
                detectHorizontalDragGestures(
                    onDragStart = { horizontalDrag = 0f },
                    onDragCancel = { horizontalDrag = 0f },
                    onDragEnd = {
                        if (kotlin.math.abs(horizontalDrag) >= swipeThresholdPx) {
                            if (horizontalDrag < 0f) model.shiftWeek(1) else model.shiftWeek(-1)
                            model.haptic("tick")
                        }
                        horizontalDrag = 0f
                    },
                ) { _, dragAmount ->
                    horizontalDrag += dragAmount
                }
            }
            .padding(horizontal = 16.dp)
            .padding(top = 8.dp),
    ) {
        // Header: Week number + Date range + Right circular < > buttons + Back to current week pill
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = "第 $week 周",
                    color = palette.ink,
                    fontSize = 27.sp,
                    fontWeight = FontWeight.Black,
                    letterSpacing = (-0.5).sp,
                )
                Text(
                    text = "${model.calendar.weekRangeMonthDayLabel(week, model.document.semester)} · 共 ${model.document.semester.totalWeeks} 周",
                    color = palette.secondary,
                    fontSize = 13.sp,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.padding(top = 2.dp),
                )
            }
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                if (week != todayWeek) {
                    StatusPill(
                        text = "回本周",
                        containerColor = palette.hero,
                        contentColor = palette.accentInk,
                        modifier = Modifier.journalPress {
                            model.backToThisWeek()
                            model.haptic("tick")
                        },
                    )
                }
                CircleActionBtn(
                    label = "‹",
                    size = 38.dp,
                    fontSize = 20.sp,
                    contentDescription = "上一周",
                    onClick = {
                        model.shiftWeek(-1)
                        model.haptic("tick")
                    },
                )
                CircleActionBtn(
                    label = "›",
                    size = 38.dp,
                    fontSize = 20.sp,
                    contentDescription = "下一周",
                    onClick = {
                        model.shiftWeek(1)
                        model.haptic("tick")
                    },
                )
            }
        }

        // Second Row: Segmented Control (周视图 / 日程列表) + Right side Next Class summary
        Row(
            modifier = Modifier.fillMaxWidth().padding(top = 10.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            IosSegmentedControl(
                items = listOf("周视图", "日程列表"),
                selectedIndex = modeIndex,
                onSelect = {
                    modeIndex = it
                    model.haptic("tick")
                },
            )
            if (focus != null) {
                val startClock = focus.timeText.substringBefore("–").trim()
                Text(
                    text = "${if (current != null) "上课中" else "下一节"} · ${focus.name} $startClock",
                    color = palette.accent,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Bold,
                    maxLines = 1,
                )
            }
        }

        // 7-Day Date Strip
        Row(
            modifier = Modifier.fillMaxWidth().padding(top = 10.dp),
            horizontalArrangement = Arrangement.spacedBy(5.dp),
        ) {
            (1..7).forEach { day ->
                val date = weekDates.getOrNull(day - 1)
                val dayNum = date?.dayOfMonth ?: day
                val hasClasses = items.any { it.weekday == day }
                // 选中跟随点击；今天只做标记（未选中时描边和数字用强调色）。
                val isSelected = day == selectedWeekday
                val isToday = WeekDaySelection.isToday(week, day, todayWeek, todayWeekday)
                val pillShape = RoundedCornerShape(16.dp)

                Column(
                    modifier = Modifier
                        .weight(1f)
                        .journalPress(scaleDown = 0.95f) {
                            selectedWeekday = WeekDaySelection.select(selectedWeekday, day)
                            model.haptic("tick")
                        }
                        .clip(pillShape)
                        .background(
                            if (isSelected) palette.accent else if (palette.isDark) palette.elevated else Color.White.copy(alpha = 0.72f),
                            pillShape,
                        )
                        .border(
                            width = 1.dp,
                            color = if (isSelected || isToday) palette.accent else palette.frostedBorder,
                            shape = pillShape,
                        )
                        .padding(vertical = 8.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Text(
                        text = ScheduleCopy.weekdayName(day),
                        color = if (isSelected) Color.White.copy(alpha = 0.9f) else palette.secondary,
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Bold,
                    )
                    Text(
                        text = "$dayNum",
                        color = when {
                            isSelected -> Color.White
                            isToday -> palette.accent
                            else -> palette.ink
                        },
                        fontSize = 17.sp,
                        fontWeight = FontWeight.Black,
                        modifier = Modifier.padding(top = 2.dp),
                    )
                    Box(
                        modifier = Modifier
                            .padding(top = 3.dp)
                            .size(4.dp)
                            .clip(androidx.compose.foundation.shape.CircleShape)
                            .background(
                                when {
                                    !hasClasses -> Color.Transparent
                                    isSelected -> Color.White
                                    else -> palette.accent
                                },
                                androidx.compose.foundation.shape.CircleShape,
                            ),
                    )
                }
            }
        }

        val holiday = model.calendar.holiday(java.time.ZonedDateTime.now(model.calendar.zone), model.document.semester)
        if (holiday != null) {
            StatusPill(
                text = "假期 · ${holiday.name}",
                containerColor = palette.courseBg("orange"),
                contentColor = palette.courseInk("orange"),
                modifier = Modifier.padding(top = 8.dp),
            )
        }

        Box(modifier = Modifier.weight(1f).fillMaxWidth().padding(top = 10.dp)) {
            if (modeIndex == 0) {
                WeekGrid(model, items, week, focus?.id, tilt, selectedWeekday)
            } else {
                WeekJournalList(model, items, week, weekDates, todayDate, selectedWeekday)
            }
        }
    }
}

@Composable
private fun WeekGrid(
    model: ClassdayModel,
    items: List<Occurrence>,
    week: Int,
    focusId: String?,
    tilt: Offset,
    selectedDay: Int,
) {
    val palette = rememberIosPalette()
    val semesterPeriods = model.document.semester.periods
    val periods = semesterPeriods.size.coerceAtLeast(1)
    val rowHeight = 46.dp
    val rowHeightPx = with(LocalDensity.current) { rowHeight.toPx() }
    var gridWidth by remember { mutableIntStateOf(0) }
    var draggingDay by remember(week) { mutableIntStateOf(0) }
    val todayDate = LocalDate.now(model.calendar.zone)
    val todayWeek = model.calendar.weekIndex(todayDate, model.document.semester)
    val today = todayDate.dayOfWeek.value

    // Compute current time red line fraction across the grid
    val nowTime = java.time.LocalTime.now(model.calendar.zone)
    val nowMinutes = nowTime.hour * 60 + nowTime.minute
    val firstStart = semesterPeriods.firstOrNull()?.let { com.classday.app.core.ClockTime.parse(it.start)?.totalMinutes } ?: 480
    val lastEnd = semesterPeriods.lastOrNull()?.let { com.classday.app.core.ClockTime.parse(it.end)?.totalMinutes } ?: 1260
    val redLinePeriodOffset: Float? = remember(nowMinutes, semesterPeriods) {
        if (semesterPeriods.isEmpty()) null
        else {
            var matched: Float? = null
            for (i in semesterPeriods.indices) {
                val p = semesterPeriods[i]
                val s = com.classday.app.core.ClockTime.parse(p.start)?.totalMinutes ?: continue
                val e = com.classday.app.core.ClockTime.parse(p.end)?.totalMinutes ?: continue
                if (nowMinutes < s && i == 0) {
                    matched = 0.2f
                    break
                }
                if (nowMinutes in s..e) {
                    val span = (e - s).coerceAtLeast(1)
                    matched = i + (nowMinutes - s).toFloat() / span.toFloat()
                    break
                }
                if (i < semesterPeriods.lastIndex) {
                    val nextS = com.classday.app.core.ClockTime.parse(semesterPeriods[i + 1].start)?.totalMinutes ?: continue
                    if (nowMinutes in e..nextS) {
                        matched = i + 1f
                        break
                    }
                }
            }
            if (matched == null && nowMinutes in firstStart..lastEnd) {
                ((nowMinutes - firstStart).toFloat() / (lastEnd - firstStart).coerceAtLeast(1).toFloat()) * periods
            } else matched
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(bottom = 110.dp)
            .offset(x = tilt.x.dp / 6, y = tilt.y.dp / 6),
    ) {
        FrostedCard(
            modifier = Modifier.fillMaxWidth(),
            cornerRadius = 22.dp,
            tier = model.tier,
            contentPadding = androidx.compose.foundation.layout.PaddingValues(8.dp),
        ) {
            Box(modifier = Modifier.fillMaxWidth().height(rowHeight * periods)) {
                // Selected-day column highlight band（本周默认是今天，点日期条可换）
                if (selectedDay in 1..7) {
                    Row(modifier = Modifier.fillMaxSize().padding(start = 30.dp)) {
                        (1..7).forEach { day ->
                            Box(
                                modifier = Modifier
                                    .weight(1f)
                                    .fillMaxSize()
                                    .padding(horizontal = 1.dp)
                                    .clip(RoundedCornerShape(12.dp))
                                    .background(
                                        if (day == selectedDay) palette.accent.copy(alpha = if (palette.isDark) 0.10f else 0.06f)
                                        else Color.Transparent,
                                        RoundedCornerShape(12.dp),
                                    ),
                            )
                        }
                    }
                }

                // Period numbers + start times + horizontal grid lines + dashed lunch/dinner dividers
                Column(modifier = Modifier.fillMaxSize()) {
                    repeat(periods) { index ->
                        val periodObj = semesterPeriods.getOrNull(index)
                        val isBreakTop = index == 4 || index == 8
                        Box(modifier = Modifier.fillMaxWidth().height(rowHeight)) {
                            if (index > 0) {
                                Canvas(modifier = Modifier.fillMaxWidth().padding(start = 30.dp).height(1.5.dp).align(Alignment.TopStart)) {
                                    if (isBreakTop) {
                                        drawLine(
                                            color = palette.secondary.copy(alpha = 0.38f),
                                            start = Offset(0f, 0f),
                                            end = Offset(size.width, 0f),
                                            strokeWidth = 1.2.dp.toPx(),
                                            pathEffect = androidx.compose.ui.graphics.PathEffect.dashPathEffect(floatArrayOf(10f, 8f), 0f),
                                        )
                                    } else {
                                        drawLine(
                                            color = palette.line.copy(alpha = 0.7f),
                                            start = Offset(0f, 0f),
                                            end = Offset(size.width, 0f),
                                            strokeWidth = 1.dp.toPx(),
                                        )
                                    }
                                }
                            }
                            Column(
                                modifier = Modifier.width(30.dp).fillMaxSize(),
                                horizontalAlignment = Alignment.CenterHorizontally,
                                verticalArrangement = Arrangement.Center,
                            ) {
                                Text(
                                    text = "${index + 1}",
                                    color = palette.ink,
                                    fontSize = 11.sp,
                                    fontWeight = FontWeight.Black,
                                )
                                if (periodObj != null) {
                                    Text(
                                        text = periodObj.start,
                                        color = palette.secondary,
                                        fontSize = 7.5.sp,
                                        fontWeight = FontWeight.SemiBold,
                                    )
                                }
                            }
                        }
                    }
                }

                // Course blocks across 7 columns
                Row(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(start = 30.dp)
                        .onSizeChanged { gridWidth = it.width },
                ) {
                    (1..7).forEach { day ->
                        Box(
                            modifier = Modifier
                                .weight(1f)
                                .fillMaxSize()
                                .zIndex(if (draggingDay == day) 2f else 0f)
                                .padding(horizontal = 1.5.dp),
                        ) {
                            items.filter { it.weekday == day }.forEach { item ->
                                val span = (item.endPeriod - item.startPeriod + 1).coerceAtLeast(1)
                                val cBg = palette.courseBg(item.colorID)
                                val cInk = palette.courseInk(item.colorID)
                                val isFocus = item.id == focusId
                                val shape = RoundedCornerShape(12.dp)
                                var dragOffset by remember(item.id, week) { mutableStateOf(Offset.Zero) }
                                val original = model.document.courses.firstOrNull { it.id == item.courseID }
                                    ?.meetings?.firstOrNull { it.id == item.meetingID }
                                val canDrag = original != null && original.weekday == item.weekday && original.startPeriod == item.startPeriod && original.endPeriod == item.endPeriod
                                val shortLoc = item.locationShort.ifBlank { item.location }

                                Column(
                                    modifier = Modifier
                                        .padding(top = rowHeight * (item.startPeriod - 1) + 1.5.dp)
                                        .offset { IntOffset(dragOffset.x.roundToInt(), dragOffset.y.roundToInt()) }
                                        .height(rowHeight * span - 3.dp)
                                        .fillMaxWidth()
                                        .clip(shape)
                                        .background(cBg, shape)
                                        .then(
                                            if (isFocus) Modifier.border(2.dp, palette.accent, shape)
                                            else Modifier.border(0.8.dp, cInk.copy(alpha = 0.16f), shape)
                                        )
                                        .pointerInput(item.id, week, gridWidth, rowHeightPx, canDrag) {
                                            detectDragGesturesAfterLongPress(
                                                onDragStart = { dragOffset = Offset.Zero; draggingDay = if (canDrag) day else 0 },
                                                onDragCancel = { dragOffset = Offset.Zero; draggingDay = 0 },
                                                onDragEnd = {
                                                    val target = com.classday.app.core.GridDragTarget.resolve(
                                                        item.weekday, item.startPeriod, item.endPeriod, periods,
                                                        dragOffset.x, dragOffset.y, gridWidth / 7f, rowHeightPx)
                                                    dragOffset = Offset.Zero
                                                    draggingDay = 0
                                                    if (!canDrag) model.banner = "本周安排有临时调整，请打开详情修改"
                                                    else if (target == null) model.banner = "超出课表范围，没有调整"
                                                    else model.moveMeeting(item.courseID, item.meetingID, target.weekday, target.startPeriod)
                                                },
                                            ) { change, amount ->
                                                change.consume()
                                                if (canDrag) dragOffset += amount
                                            }
                                        }
                                        .clickable { model.open(Screen.Detail(item.courseID, item.meetingID, week)) }
                                        .semantics { contentDescription = "${item.name} ${ScheduleCopy.weekdayName(item.weekday)} ${item.timeText} ${item.parityLabel}" }
                                        .padding(horizontal = 4.dp, vertical = 5.dp),
                                    verticalArrangement = Arrangement.SpaceBetween,
                                ) {
                                    Text(
                                        text = item.name,
                                        color = cInk,
                                        fontWeight = FontWeight.Black,
                                        fontSize = 10.5.sp,
                                        lineHeight = 12.5.sp,
                                        maxLines = 2,
                                    )
                                    Column {
                                        if (shortLoc.isNotBlank()) {
                                            Text(
                                                text = shortLoc,
                                                color = cInk.copy(alpha = 0.84f),
                                                fontSize = 8.5.sp,
                                                fontWeight = FontWeight.Bold,
                                                lineHeight = 10.sp,
                                                maxLines = 2,
                                            )
                                        }
                                        if (item.parityLabel.isNotEmpty()) {
                                            Text(
                                                text = item.parityLabel,
                                                color = cInk,
                                                fontSize = 8.sp,
                                                fontWeight = FontWeight.Bold,
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Current Time Red Line + Red Dot
                if (redLinePeriodOffset != null) {
                    val lineTop = (rowHeight * redLinePeriodOffset).coerceIn(4.dp, rowHeight * periods - 4.dp)
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(start = 26.dp, top = lineTop)
                            .zIndex(3f),
                    ) {
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(start = 4.dp)
                                .height(2.dp)
                                .align(Alignment.CenterStart)
                                .background(Color(0xFFFF5A5F)),
                        )
                        Box(
                            modifier = Modifier
                                .size(10.dp)
                                .align(Alignment.CenterStart)
                                .clip(androidx.compose.foundation.shape.CircleShape)
                                .background(Color(0xFFFF5A5F), androidx.compose.foundation.shape.CircleShape)
                                .border(2.dp, Color.White, androidx.compose.foundation.shape.CircleShape),
                        )
                    }
                }
            }
        }
        Text(
            text = "长按课程拖动可调整整学期，冲突时不会放下，可撤销；临时调课请打开详情。",
            fontSize = 11.sp,
            color = palette.secondary,
            modifier = Modifier.padding(top = 8.dp, start = 4.dp),
        )
    }
}

@Composable
private fun WeekJournalList(
    model: ClassdayModel,
    items: List<Occurrence>,
    week: Int,
    weekDates: List<LocalDate>,
    todayDate: LocalDate,
    selectedDay: Int,
) {
    val palette = rememberIosPalette()
    val listScroll = rememberScrollState()
    val dayOffsets = remember(week) { mutableStateMapOf<Int, Int>() }
    // 点日期条后把列表滚到那一天。
    LaunchedEffect(week, selectedDay, dayOffsets[selectedDay]) {
        dayOffsets[selectedDay]?.let { listScroll.animateScrollTo(it) }
    }
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(listScroll)
            .padding(bottom = 110.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        (1..7).forEach { weekday ->
            val date = weekDates.getOrNull(weekday - 1)
            val isToday = date == todayDate
            val dayItems = items.filter { it.weekday == weekday }.sortedBy { it.startPeriod }
            val dayHoliday = date?.let {
                model.calendar.holiday(it.atStartOfDay(model.calendar.zone), model.document.semester)
            }

            val isSelectedDay = weekday == selectedDay
            FrostedCard(
                modifier = Modifier.fillMaxWidth().onGloballyPositioned {
                    dayOffsets[weekday] = it.positionInParent().y.toInt()
                },
                cornerRadius = 22.dp,
                tier = model.tier,
                borderColor = when {
                    isSelectedDay -> palette.accent.copy(alpha = 0.75f)
                    isToday -> palette.accent.copy(alpha = 0.45f)
                    else -> null
                },
                borderWidth = if (isToday || isSelectedDay) 1.5.dp else 1.dp,
                contentPadding = androidx.compose.foundation.layout.PaddingValues(14.dp),
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    verticalAlignment = Alignment.Top,
                ) {
                    Column(modifier = Modifier.width(62.dp)) {
                        Text(
                            text = "${date?.dayOfMonth ?: weekday}",
                            color = if (isToday) palette.accent else palette.ink,
                            fontSize = 24.sp,
                            fontWeight = FontWeight.Black,
                        )
                        Text(
                            text = ScheduleCopy.weekdayShort(weekday),
                            color = palette.secondary,
                            fontSize = 11.5.sp,
                            fontWeight = FontWeight.SemiBold,
                        )
                        if (isToday) {
                            StatusPill(
                                text = "今天",
                                containerColor = palette.hero,
                                contentColor = palette.accentInk,
                                modifier = Modifier.padding(top = 6.dp),
                            )
                        } else if (dayHoliday != null) {
                            StatusPill(
                                text = dayHoliday.name,
                                containerColor = palette.courseBg("orange"),
                                contentColor = palette.courseInk("orange"),
                                modifier = Modifier.padding(top = 6.dp),
                            )
                        }
                    }

                    Column(
                        modifier = Modifier.weight(1f),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        if (dayItems.isEmpty()) {
                            Text(
                                text = if (dayHoliday != null) "假期休整，没有课程安排" else "这一天没有课，适合自习或休息",
                                color = palette.secondary,
                                fontSize = 13.sp,
                                modifier = Modifier.padding(vertical = 8.dp),
                            )
                        } else {
                            dayItems.forEach { item ->
                                val cInk = palette.courseInk(item.colorID)
                                val cBg = palette.courseBg(item.colorID)
                                val rowShape = RoundedCornerShape(14.dp)
                                Row(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .journalPress { model.open(Screen.Detail(item.courseID, item.meetingID, week)) }
                                        .clip(rowShape)
                                        .background(cBg.copy(alpha = if (palette.isDark) 0.45f else 0.55f), rowShape)
                                        .padding(horizontal = 12.dp, vertical = 10.dp),
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                                ) {
                                    Box(
                                        modifier = Modifier
                                            .width(4.dp)
                                            .height(34.dp)
                                            .clip(RoundedCornerShape(2.dp))
                                            .background(cInk, RoundedCornerShape(2.dp)),
                                    )
                                    Column(modifier = Modifier.weight(1f)) {
                                        Text(
                                            text = item.name,
                                            color = palette.ink,
                                            fontSize = 14.5.sp,
                                            fontWeight = FontWeight.Black,
                                        )
                                        Text(
                                            text = "${item.timeText} · ${item.location.ifBlank { "未设教室" }}",
                                            color = palette.secondary,
                                            fontSize = 11.5.sp,
                                            modifier = Modifier.padding(top = 2.dp),
                                        )
                                    }
                                    Text("›", color = palette.secondary, fontSize = 18.sp, fontWeight = FontWeight.Bold)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun FinalScorePanel(scheme: com.classday.app.core.GradeScheme, onSaveScores: (Map<String, String>) -> Unit) {
    var editScores by remember { mutableStateOf(false) }
    var scoreEntries by remember(scheme) { mutableStateOf(scheme.components.associate { it.id to scheme.scores[it.id]?.toString().orEmpty() }) }
    var finalID by remember(scheme.components) { mutableStateOf("") }
    var targetText by remember { mutableStateOf("80") }
    Text("期末成绩预测", fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 12.dp))
    TextButton(onClick = { editScores = !editScores }) { Text(if (editScores) "收起分项成绩" else "录入 / 修改分项成绩") }
    if (editScores) {
        scheme.components.forEach { component ->
            OutlinedTextField(scoreEntries[component.id].orEmpty(), { scoreEntries = scoreEntries + (component.id to it) },
                label = { Text("${component.name}（满分 ${scheme.scale}）") }, modifier = Modifier.fillMaxWidth())
        }
        Text("空白保留原成绩，不会清除；保存后按已有算法更新总成绩，算法分项未齐全时保留原总成绩。试算要使用新成绩，请先保存。", fontSize = 12.sp)
        Button(enabled = scoreEntries.values.any { it.isNotBlank() }, onClick = { onSaveScores(scoreEntries) }) { Text("保存分项成绩") }
    }
    Text("选择期末分项。先录全参与计算的其他分项成绩；有多条算法时按最容易达到的一条算。不改成绩，已录入的期末分数也不计入。", fontSize = 12.sp)
    Row(Modifier.horizontalScroll(rememberScrollState())) {
        scheme.components.forEach { component ->
            FilterChip(selected = finalID == component.id, onClick = { finalID = component.id }, label = { Text(component.name) })
        }
    }
    OutlinedTextField(targetText, { targetText = it }, label = { Text("目标总分（百分制 0–100）") })
    if (finalID.isNotEmpty()) {
        fun answer(target: Double): String {
            val result = com.classday.app.core.FinalScorePrediction.evaluate(scheme, finalID, target)
            return when (result.status) {
                com.classday.app.core.PredictionStatus.required -> "期末至少考 ${"%.2f".format(kotlin.math.ceil(result.minimum!! * 100) / 100)} 分（满分 ${"%.2f".format(scheme.scale).trimEnd('0').trimEnd('.')}，按 0.01 分向上取整）"
                com.classday.app.core.PredictionStatus.alreadyReached -> "按当前规则，期末考 0 分也能达到这个目标"
                com.classday.app.core.PredictionStatus.impossible -> "按当前规则，期末考满分也达不到这个目标"
                com.classday.app.core.PredictionStatus.missingScores -> "请先录全参与计算的其他分项成绩（期末除外）"
                com.classday.app.core.PredictionStatus.invalidRule -> "请检查满分、分项、成绩和每条算法的权重（同一条算法内按小数填，合计为 1，如 30% 写 0.3）"
            }
        }
        Text("及格（总分 60%）：${answer(60.0)}")
        val target = targetText.toDoubleOrNull()
        Text(if (target == null || !target.isFinite() || target !in 0.0..100.0) "目标请输入 0–100" else "自定目标：${answer(target)}")
        Text("结果只按加权规则试算，不含学校另设的期末最低分、四舍五入或补考限制；及格线请按学校实际要求核对。", fontSize = 12.sp)
    }
}

private fun Modifier.alignIfPossible() = this

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CourseDetailBottomSheet(
    model: ClassdayModel,
    screen: Screen.Detail,
    nowMillis: Long,
    onDismiss: () -> Unit,
) {
    val palette = rememberIosPalette()
    val sheetState = androidx.compose.material3.rememberModalBottomSheetState(skipPartiallyExpanded = false)
    androidx.compose.material3.ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        shape = RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp),
        containerColor = if (palette.isDark) palette.card else Color.White.copy(alpha = 0.96f),
        dragHandle = {
            Box(
                modifier = Modifier
                    .padding(top = 10.dp, bottom = 6.dp)
                    .width(40.dp)
                    .height(5.dp)
                    .clip(RoundedCornerShape(3.dp))
                    .background(if (palette.isDark) palette.line else Color(0xFFD0D6E2)),
            )
        },
    ) {
        CourseDetailContent(
            model = model,
            screen = screen,
            nowMillis = nowMillis,
            inSheet = true,
            onClose = onDismiss,
        )
    }
}

@Composable
private fun DetailPage(model: ClassdayModel, screen: Screen.Detail) {
    CourseDetailContent(
        model = model,
        screen = screen,
        nowMillis = System.currentTimeMillis(),
        inSheet = false,
        onClose = model::back,
    )
}

@Composable
private fun CourseDetailContent(
    model: ClassdayModel,
    screen: Screen.Detail,
    nowMillis: Long,
    inSheet: Boolean,
    onClose: () -> Unit,
) {
    val palette = rememberIosPalette()
    val course = model.document.courses.firstOrNull { it.id.equals(screen.courseId, ignoreCase = true) }
    if (course == null) {
        if (!inSheet) PageTitle("课程", onClose)
        Text("这门课不在当前课表里", color = palette.secondary, modifier = Modifier.padding(16.dp))
        return
    }
    val item = model.occurrences().firstOrNull { it.courseID.equals(course.id, true) && (screen.meetingId == null || it.meetingID.equals(screen.meetingId, true)) }
        ?: ScheduleEngine.occurrences(screen.week, listOf(course), model.document.semester, model.calendar, model.document.scheduleContext).firstOrNull()
    var moveWeekday by remember(item?.id) { mutableIntStateOf(item?.weekday ?: 1) }
    var movePeriod by remember(item?.id) { mutableIntStateOf(item?.startPeriod ?: 1) }
    var showAddHomework by remember { mutableStateOf(false) }
    var showAdvanced by remember { mutableStateOf(false) }
    val context = LocalContext.current

    if (showAddHomework) {
        androidx.compose.ui.window.Dialog(onDismissRequest = { showAddHomework = false }) {
            Card(shape = RoundedCornerShape(22.dp), colors = CardDefaults.cardColors(containerColor = palette.card)) {
                Column(Modifier.heightIn(max = 520.dp).verticalScroll(rememberScrollState()).padding(16.dp)) {
                    Text("添加作业 · ${course.name}", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                    val initialTask = remember(course.name) {
                        com.classday.app.core.HomeworkTask(
                            id = "",
                            courseName = course.name,
                            title = "",
                            dueISO = java.time.LocalDateTime.now().plusDays(1).withHour(23).withMinute(59).withSecond(0).withNano(0).toString(),
                        )
                    }
                    WorkForm(initialTask, onCancel = { showAddHomework = false }) { cName, title, due ->
                        val saved = model.saveHomework(null, cName.ifBlank { course.name }, title, due)
                        if (saved) showAddHomework = false
                        saved
                    }
                }
            }
        }
    }

    val weekdaysText = course.meetings.map { ScheduleCopy.weekdayName(it.weekday) }.distinct().joinToString("、")
    val cBg = palette.courseBg(course.colorID)
    val cInk = palette.courseInk(course.colorID)
    val leadMinutes = CourseReminder.effectiveLead(course.reminderLeadMinutes, model.document.semester.defaultReminderMinutes)

    // 同名考试里优先显示正在考或下一场；都已结束才显示最近结束的那场，并标「已结束」。
    val courseExamBuckets = ExamTimeline.classify(
        model.document.exams.filter {
            it.courseName.contains(course.name, ignoreCase = true) || course.name.contains(it.courseName, ignoreCase = true)
        },
        nowMillis,
    ) { CivilStamp.instant(it, model.calendar)?.toEpochMilli() }
    val matchingExam = courseExamBuckets.focus ?: courseExamBuckets.past.firstOrNull()
    val matchingHomework = model.document.homework.filter {
        !it.done && (it.courseName.equals(course.name, ignoreCase = true) || it.courseName.contains(course.name, ignoreCase = true))
    }

    val statusPillText = if (item != null) {
        when {
            item.startEpochMillis <= nowMillis && nowMillis < item.endEpochMillis ->
                "正在上课 · 还剩 ${CountdownCopy.remaining(item.endEpochMillis, nowMillis)}"
            item.startEpochMillis > nowMillis ->
                "${CountdownCopy.remaining(item.startEpochMillis, nowMillis)}后上课"
            else -> "${ScheduleCopy.weekdayName(item.weekday)} ${item.timeText}"
        }
    } else {
        ScheduleCopy.weekList(course.weeks)
    }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 18.dp)
            .padding(top = if (inSheet) 4.dp else 12.dp, bottom = 36.dp),
    ) {
        if (!inSheet) {
            PageTitle(course.name, onClose)
        }

        // Top Header: 62dp CourseGlyphTile + Course Name + Teacher / Weekdays / Weeks
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            CourseGlyphTile(
                name = course.name,
                colorID = course.colorID,
                size = 62.dp,
                cornerRadius = 20.dp,
                fontSize = 28.sp,
            )
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = course.name,
                    color = palette.ink,
                    fontSize = 22.sp,
                    fontWeight = FontWeight.Black,
                )
                Text(
                    text = listOfNotNull(
                        course.teacher.takeIf { it.isNotBlank() },
                        weekdaysText.takeIf { it.isNotBlank() }?.let { "每$it" },
                        ScheduleCopy.weekList(course.weeks),
                    ).joinToString(" · "),
                    color = palette.secondary,
                    fontSize = 13.sp,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.padding(top = 4.dp),
                )
            }
        }

        // Status Pills Row
        Row(
            modifier = Modifier.fillMaxWidth().padding(top = 12.dp),
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            StatusPill(
                text = statusPillText,
                containerColor = cBg,
                contentColor = cInk,
            )
            if (item != null) {
                StatusPill(
                    text = "第 ${item.startPeriod}–${item.endPeriod} 节",
                    containerColor = palette.elevated,
                    contentColor = palette.ink,
                )
            }
            if (course.kind.isNotBlank()) {
                StatusPill(
                    text = course.kind,
                    containerColor = palette.elevated,
                    contentColor = palette.ink,
                )
            }
        }

        Spacer(Modifier.height(10.dp))

        // Key-Value Rows: 时间 / 教室 / 考试 / 作业
        DetailKvRow(
            label = "时间",
            value = item?.let { "${it.timeText}${if (it.parityLabel.isNotBlank()) " · ${it.parityLabel}" else ""}" } ?: "未安排",
            valueColor = palette.ink,
        )
        DetailKvRow(
            label = "教室",
            value = (item?.location ?: course.location).ifBlank { "未设教室" },
            valueColor = palette.ink,
        )
        val examValue = if (matchingExam != null) {
            val inst = CivilStamp.instant(matchingExam.startISO, model.calendar)
            val z = inst?.atZone(model.calendar.zone)
            val days = ExamTimeline.daysUntilStart(inst?.toEpochMilli(), nowMillis)
            val status = when {
                days != null -> "$days 天后"
                matchingExam in courseExamBuckets.ongoing -> "考试中"
                matchingExam in courseExamBuckets.past -> "已结束"
                else -> "时间待定"
            }
            if (z != null) {
                "${z.year}-${"%02d".format(z.monthValue)}-${"%02d".format(z.dayOfMonth)} ${"%02d:%02d".format(z.hour, z.minute)} · $status"
            } else {
                "${matchingExam.startISO} · $status"
            }
        } else {
            "暂无安排"
        }
        DetailKvRow(
            label = "考试",
            value = examValue,
            valueColor = if (matchingExam != null) palette.courseInk("orange") else palette.secondary,
        )
        val hwValue = if (matchingHomework.isNotEmpty()) {
            val firstHw = matchingHomework.first()
            val dueInst = CivilStamp.instant(firstHw.dueISO, model.calendar)
            val dueDate = dueInst?.atZone(model.calendar.zone)?.toLocalDate()
            val today = Instant.ofEpochMilli(nowMillis).atZone(model.calendar.zone).toLocalDate()
            val d = if (dueDate != null) java.time.temporal.ChronoUnit.DAYS.between(today, dueDate) else 0L
            val suffix = when {
                d < 0 -> "已逾期"
                d == 0L -> "今天截止"
                d == 1L -> "明天截止"
                else -> "${d}天后截止"
            }
            "${firstHw.title}（$suffix）"
        } else {
            "暂无待办"
        }
        DetailKvRow(
            label = "作业",
            value = hwValue,
            valueColor = if (matchingHomework.isNotEmpty()) palette.ink else palette.secondary,
            showDivider = false,
        )

        if (course.note.isNotBlank()) {
            Text(course.note, color = palette.secondary, fontSize = 12.5.sp, modifier = Modifier.padding(top = 6.dp))
        }

        // 教室校准状态：未校准的教室，导航只能靠模糊搜索，这里给它一个显眼入口
        val roomPin = model.document.rooms.firstOrNull { it.name == course.location }
        val roomCalibrated = com.classday.app.core.MapLinks.hasPreciseQuery(course.location, roomPin)
        if (course.location.isNotBlank()) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 12.dp)
                    .journalPress {
                        if (!roomCalibrated) {
                            Maps.open(
                                context = context,
                                location = course.location,
                                pin = roomPin,
                                onBindQuery = { model.bindRoomQuery(course.location, it) },
                                onError = { model.banner = it },
                            )
                        }
                    },
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = if (roomCalibrated) "✅ 教室已校准，可直接导航" else "🎯 教室未校准 · 点这里填一次关键词，以后导航更准",
                    color = if (roomCalibrated) palette.secondary else palette.accent,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Medium,
                )
            }
        }
        // Row 1 Buttons: 📍 导航到教室 (Primary) + ✏️ 编辑课程 (Secondary)
        val btnShape = RoundedCornerShape(16.dp)
        Row(
            modifier = Modifier.fillMaxWidth().padding(top = 14.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Box(
                modifier = Modifier
                    .weight(1f)
                    .height(50.dp)
                    .journalPress {
                        val pin = model.document.rooms.firstOrNull { it.name == course.location }
                        Maps.open(
                            context = context,
                            location = course.location,
                            pin = pin,
                            onBindQuery = { model.bindRoomQuery(course.location, it) },
                            onError = { model.banner = it },
                        )
                    }
                    .clip(btnShape)
                    .background(palette.accent, btnShape),
                contentAlignment = Alignment.Center,
            ) {
                Text("📍 导航到教室", color = Color.White, fontSize = 15.sp, fontWeight = FontWeight.Bold)
            }
            Box(
                modifier = Modifier
                    .weight(1f)
                    .height(50.dp)
                    .journalPress { model.open(Screen.Editor(course.id)) }
                    .clip(btnShape)
                    .background(palette.segment, btnShape),
                contentAlignment = Alignment.Center,
            ) {
                Text("✏️ 编辑课程", color = palette.ink, fontSize = 15.sp, fontWeight = FontWeight.Bold)
            }
        }

        // Row 2 Buttons: ⏰ 提前 N 分钟提醒 + 📝 加作业
        Row(
            modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Box(
                modifier = Modifier
                    .weight(1f)
                    .height(44.dp)
                    .journalPress { model.cycleCourseReminder(course.id) }
                    .clip(btnShape)
                    .background(palette.elevated, btnShape),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    text = if (leadMinutes > 0) "⏰ 提前 $leadMinutes 分钟提醒" else "⏰ 开启课前提醒",
                    color = palette.ink,
                    fontSize = 13.5.sp,
                    fontWeight = FontWeight.Bold,
                )
            }
            Box(
                modifier = Modifier
                    .weight(1f)
                    .height(44.dp)
                    .journalPress { showAddHomework = true }
                    .clip(btnShape)
                    .background(palette.elevated, btnShape),
                contentAlignment = Alignment.Center,
            ) {
                Text("📝 加作业", color = palette.ink, fontSize = 13.5.sp, fontWeight = FontWeight.Bold)
            }
        }

        // Expandable / Full-screen Schedule Adjustments & Grade Prediction (preserves all capabilities)
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 14.dp)
                .journalPress { showAdvanced = !showAdvanced },
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = if (showAdvanced) "收起调课与更多操作" else "调课、单双周与成绩试算",
                color = palette.secondary,
                fontSize = 13.sp,
                fontWeight = FontWeight.Bold,
            )
            Text(
                text = if (showAdvanced) "▴" else "▾",
                color = palette.secondary,
                fontSize = 14.sp,
                fontWeight = FontWeight.Bold,
            )
        }

        if (showAdvanced || !inSheet) {
            Spacer(Modifier.height(10.dp))
            course.grade?.let { Text("成绩 $it", color = palette.ink, fontWeight = FontWeight.SemiBold) }
            course.gradeScheme?.normalizedFinal?.let { Text("规则折合 ${"%.1f".format(it)}", color = palette.secondary, fontSize = 12.sp) }
            course.gradeScheme?.let { FinalScorePanel(it) { entries -> model.saveGradeScores(course.id, entries) } }

            if (item != null) {
                Row(
                    modifier = Modifier.padding(top = 8.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Button(onClick = { model.cancelThisWeek(item) }) { Text("本周停课") }
                    Button(onClick = { model.delayThisWeek(item) }) { Text("推迟 10 分钟") }
                    TextButton(onClick = { model.clearThisWeek(item) }) { Text("恢复本周") }
                }
                Text("本周调课", fontWeight = FontWeight.Bold, color = palette.ink, modifier = Modifier.padding(top = 8.dp))
                Stepper("星期 $moveWeekday", { moveWeekday = (moveWeekday - 1).coerceAtLeast(1) }, { moveWeekday = (moveWeekday + 1).coerceAtMost(7) })
                Stepper("开始节次 $movePeriod", { movePeriod = (movePeriod - 1).coerceAtLeast(1) }, { movePeriod = (movePeriod + 1).coerceAtMost(model.document.semester.periods.size) })
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(onClick = { model.moveThisWeek(item, moveWeekday, movePeriod) }) { Text("只改本周") }
                    Button(onClick = { model.moveMeeting(item.courseID, item.meetingID, moveWeekday, movePeriod) }) { Text("调整整学期") }
                }
                Text("单双周", fontWeight = FontWeight.Bold, color = palette.ink, modifier = Modifier.padding(top = 8.dp))
                val parity = model.document.scheduleContext.parity(item.meetingID)
                Row {
                    WeekParity.entries.forEach { option ->
                        FilterChip(
                            selected = parity == option,
                            onClick = { model.setParity(item.meetingID, option) },
                            label = { Text(option.title) },
                            modifier = Modifier.padding(end = 6.dp),
                        )
                    }
                }
            }
            Row(
                modifier = Modifier.fillMaxWidth().padding(top = 12.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                TextButton(onClick = { model.open(Screen.Editor(course.id)) }) { Text("编辑") }
                TextButton(onClick = { model.deleteCourse(course.id) }) {
                    Text("删除课程", color = Color(0xFFFF3B30), fontWeight = FontWeight.Bold)
                }
            }
        }
    }
}

@Composable
private fun DetailKvRow(
    label: String,
    value: String,
    valueColor: Color,
    showDivider: Boolean = true,
) {
    val palette = rememberIosPalette()
    Column(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(vertical = 10.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(text = label, color = palette.secondary, fontSize = 13.5.sp, fontWeight = FontWeight.SemiBold)
            Text(text = value, color = valueColor, fontSize = 14.sp, fontWeight = FontWeight.Bold)
        }
        if (showDivider) {
            Box(modifier = Modifier.fillMaxWidth().height(1.dp).background(palette.line))
        }
    }
}

@Composable
private fun Stepper(label: String, minus: () -> Unit, plus: () -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        TextButton(onClick = minus) { Text("−") }
        Text(label, modifier = Modifier.width(120.dp))
        TextButton(onClick = plus) { Text("+") }
    }
}

@Composable
private fun EditorPage(model: ClassdayModel, courseId: String?) {
    val existing = model.document.courses.firstOrNull { it.id.equals(courseId, true) }
    var course by remember { mutableStateOf(existing ?: model.blankCourse()) }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp)) {
        PageTitle(if (existing == null) "新课程" else "编辑课程", model::back)
        Field("名称", course.name) { course = course.copy(name = it) }
        Field("教师", course.teacher) { course = course.copy(teacher = it) }
        Field("地点", course.location) { course = course.copy(location = it) }
        Field("班级", course.className) { course = course.copy(className = it) }
        Field("类型", course.kind) { course = course.copy(kind = it) }
        Field("备注", course.note) { course = course.copy(note = it) }
        Field("周次，例如 1-16", course.weeks.let { if (it.isEmpty()) "" else "${it.first()}-${it.last()}" }) { raw ->
            val numbers = Regex("\\d+").findAll(raw).map { it.value.toInt() }.toList()
            val weeks = if (numbers.size >= 2) (numbers[0]..numbers[1]).toList() else numbers
            course = course.copy(weeks = weeks)
        }
        Text("颜色", modifier = Modifier.padding(top = 8.dp))
        Row(Modifier.horizontalScroll(rememberScrollState())) {
            com.classday.app.core.CourseColors.all.forEach { id ->
                FilterChip(selected = course.colorID == id, onClick = { course = course.copy(colorID = id) }, label = { Text(id) }, modifier = Modifier.padding(end = 6.dp))
            }
        }
        course.meetings.forEachIndexed { index, meeting ->
            Text("时间 ${index + 1}", fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 8.dp))
            Stepper("周${meeting.weekday}", { course = course.replaceMeeting(index) { it.copy(weekday = (it.weekday - 1).coerceAtLeast(1)) } }, { course = course.replaceMeeting(index) { it.copy(weekday = (it.weekday + 1).coerceAtMost(7)) } })
            Stepper("第 ${meeting.startPeriod}–${meeting.endPeriod} 节", {
                course = course.replaceMeeting(index) { it.copy(startPeriod = (it.startPeriod - 1).coerceAtLeast(1), endPeriod = (it.endPeriod - 1).coerceAtLeast(it.startPeriod)) }
            }, {
                val max = model.document.semester.periods.size
                course = course.replaceMeeting(index) { it.copy(endPeriod = (it.endPeriod + 1).coerceAtMost(max)) }
            })
            TextButton(onClick = { course = course.copy(meetings = course.meetings.filterIndexed { i, _ -> i != index }) }) { Text("删除这个时间") }
        }
        TextButton(onClick = { course = course.copy(meetings = course.meetings + Meeting(newId(), 1, 1, 2)) }) { Text("加一个上课时间") }
        Button(onClick = { model.saveCourse(course) }, modifier = Modifier.padding(top = 12.dp)) { Text("保存") }
    }
}

private fun Course.replaceMeeting(index: Int, block: (Meeting) -> Meeting) =
    copy(meetings = meetings.mapIndexed { i, meeting -> if (i == index) block(meeting) else meeting })

@Composable
private fun Field(label: String, value: String, onChange: (String) -> Unit) {
    OutlinedTextField(value = value, onValueChange = onChange, label = { Text(label) }, modifier = Modifier.fillMaxWidth().padding(top = 6.dp))
}

@Composable
private fun CountdownPage(model: ClassdayModel, now: Long) {
    val palette = rememberIosPalette()
    var tabIndex by rememberSaveable { mutableIntStateOf(0) }
    var showExam by remember { mutableStateOf(false) }
    var showWork by remember { mutableStateOf(false) }
    var showAddMenu by remember { mutableStateOf(false) }
    var editingExam by remember { mutableStateOf<com.classday.app.core.ExamEvent?>(null) }
    var editingWork by remember { mutableStateOf<com.classday.app.core.HomeworkTask?>(null) }
    var deleteAction by remember { mutableStateOf<(() -> Unit)?>(null) }

    if (deleteAction != null) {
        AlertDialog(
            onDismissRequest = { deleteAction = null },
            title = { Text("确认删除这项安排？", fontWeight = FontWeight.Bold) },
            text = { Text("只删除当前课表中的这一项，其他课程与安排保留。") },
            confirmButton = {
                TextButton(onClick = {
                    val action = deleteAction
                    deleteAction = null
                    action?.invoke()
                }) { Text("删除", color = Color(0xFFFF3B30), fontWeight = FontWeight.Bold) }
            },
            dismissButton = {
                TextButton(onClick = { deleteAction = null }) { Text("取消") }
            },
        )
    }

    if (showExam) {
        androidx.compose.ui.window.Dialog(onDismissRequest = { showExam = false }) {
            Card(shape = RoundedCornerShape(22.dp), colors = CardDefaults.cardColors(containerColor = palette.card)) {
                Column(Modifier.heightIn(max = 560.dp).verticalScroll(rememberScrollState()).padding(16.dp)) {
                    Text(if (editingExam == null) "添加考试" else "编辑考试", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                    ExamForm(editingExam, onCancel = { showExam = false }) { name, start, end, place ->
                        val saved = model.saveExam(editingExam, name, start, end, place)
                        if (saved) showExam = false
                        saved
                    }
                }
            }
        }
    }

    if (showWork) {
        androidx.compose.ui.window.Dialog(onDismissRequest = { showWork = false }) {
            Card(shape = RoundedCornerShape(22.dp), colors = CardDefaults.cardColors(containerColor = palette.card)) {
                Column(Modifier.heightIn(max = 520.dp).verticalScroll(rememberScrollState()).padding(16.dp)) {
                    Text(if (editingWork == null) "添加作业" else "编辑作业", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                    WorkForm(editingWork, onCancel = { showWork = false }) { course, title, due ->
                        val saved = model.saveHomework(editingWork, course, title, due)
                        if (saved) showWork = false
                        saved
                    }
                }
            }
        }
    }

    val pendingHwCount = model.document.homework.count { !it.done }
    val examBuckets = ExamTimeline.classify(model.document.exams, now) {
        CivilStamp.instant(it, model.calendar)?.toEpochMilli()
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 16.dp)
            .padding(top = 8.dp, bottom = 110.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        // Header: Title + Subtitle + Top-Right '+' Button
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = "课程",
                    color = palette.ink,
                    fontSize = 27.sp,
                    fontWeight = FontWeight.Black,
                    letterSpacing = (-0.5).sp,
                )
                Text(
                    text = "全部课程、考试、作业和成绩",
                    color = palette.secondary,
                    fontSize = 13.sp,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.padding(top = 2.dp),
                )
            }
            Box {
                CircleActionBtn(
                    label = "+",
                    size = 40.dp,
                    fontSize = 22.sp,
                    contentDescription = "添加学习安排",
                    onClick = {
                        when (tabIndex) {
                            0 -> {
                                editingExam = null
                                showExam = true
                            }
                            1 -> {
                                editingWork = null
                                showWork = true
                            }
                            else -> showAddMenu = true
                        }
                    },
                )
                androidx.compose.material3.DropdownMenu(
                    expanded = showAddMenu,
                    onDismissRequest = { showAddMenu = false },
                ) {
                    androidx.compose.material3.DropdownMenuItem(
                        text = { Text("添加考试", fontWeight = FontWeight.SemiBold) },
                        onClick = {
                            showAddMenu = false
                            editingExam = null
                            showExam = true
                        },
                    )
                    androidx.compose.material3.DropdownMenuItem(
                        text = { Text("添加作业", fontWeight = FontWeight.SemiBold) },
                        onClick = {
                            showAddMenu = false
                            editingWork = null
                            showWork = true
                        },
                    )
                }
            }
        }

        // 3-Segment Control: 考试 / 作业 · N / 成绩
        IosSegmentedControl(
            items = listOf("全部课程", "考试", "作业 · $pendingHwCount", "成绩"),
            selectedIndex = tabIndex,
            onSelect = {
                tabIndex = it
                model.haptic("tick")
            },
            fullWidth = true,
        )

        when (tabIndex) {
            0 -> {
                // All Courses Segment
                CourseListSection(model, palette)
            }
            1 -> {
                // Exams Segment
                if (model.document.exams.isEmpty()) {
                    FrostedCard(modifier = Modifier.fillMaxWidth(), cornerRadius = 20.dp, tier = model.tier) {
                        Text("还没有考试，可手动添加或到「我的 → 数据」导入日历文件。", color = palette.secondary, fontSize = 13.5.sp)
                        TextButton(onClick = { editingExam = null; showExam = true }) {
                            Text("添加考试", fontWeight = FontWeight.Bold)
                        }
                    }
                } else {
                    val nearest = examBuckets.focus
                    if (nearest == null) {
                        FrostedCard(modifier = Modifier.fillMaxWidth(), cornerRadius = 20.dp, tier = model.tier) {
                            Text("近期没有待考的考试，已结束的考试列在下方。", color = palette.secondary, fontSize = 13.5.sp)
                            TextButton(onClick = { editingExam = null; showExam = true }) {
                                Text("添加考试", fontWeight = FontWeight.Bold)
                            }
                        }
                    } else {
                        val nearestStart = CivilStamp.instant(nearest.startISO, model.calendar)
                        val nearestEnd = CivilStamp.instant(nearest.endISO, model.calendar)
                        // focus 只会是进行中或未开始的考试，不再把已结束考试压成「0 天 0 小时」。
                        val nearestOngoing = nearest in examBuckets.ongoing
                        val totalHours = nearestStart?.toEpochMilli()?.takeIf { it > now }?.let { (it - now) / 3_600_000L }
                        val zStart = nearestStart?.atZone(model.calendar.zone)
                        val zEnd = nearestEnd?.atZone(model.calendar.zone)
                        val nearestTimeLine = if (zStart != null && zEnd != null) {
                            ExamCopy.nearestLine(
                                month = zStart.monthValue,
                                day = zStart.dayOfMonth,
                                weekday = zStart.dayOfWeek.value,
                                startHour = zStart.hour,
                                startMinute = zStart.minute,
                                endHour = zEnd.hour,
                                endMinute = zEnd.minute,
                                location = nearest.location,
                            )
                        } else {
                            "${nearest.startISO} – ${nearest.endISO} · ${ExamCopy.locationLabel(nearest.location)}"
                        }

                        val orangeBg = palette.courseBg("orange")
                        val orangeInk = palette.courseInk("orange")
                        val heroShape = RoundedCornerShape(26.dp)

                        SwipeRevealItem(
                            key = nearest.id,
                            onEdit = { editingExam = nearest; showExam = true },
                            onDelete = { deleteAction = { model.deleteExam(nearest.id) } },
                        ) {
                            Column(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .clip(heroShape)
                                    .background(
                                        brush = androidx.compose.ui.graphics.Brush.linearGradient(
                                            colors = listOf(
                                                orangeBg,
                                                if (palette.isDark) orangeBg.copy(alpha = 0.72f) else Color(0xFFFFF4EB),
                                            ),
                                        ),
                                        shape = heroShape,
                                    )
                                    .border(1.dp, palette.frostedBorder, heroShape)
                                    .padding(18.dp),
                            ) {
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalArrangement = Arrangement.SpaceBetween,
                                    verticalAlignment = Alignment.CenterVertically,
                                ) {
                                    StatusPill(
                                        text = if (nearestOngoing) "正在考试" else "最近一场",
                                        containerColor = if (palette.isDark) Color.White.copy(alpha = 0.14f) else Color.White.copy(alpha = 0.75f),
                                        contentColor = orangeInk,
                                    )
                                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                        Text(
                                            text = "编辑",
                                            color = orangeInk,
                                            fontSize = 12.sp,
                                            fontWeight = FontWeight.Bold,
                                            modifier = Modifier.journalPress { editingExam = nearest; showExam = true },
                                        )
                                        Text(
                                            text = "删除",
                                            color = orangeInk.copy(alpha = 0.78f),
                                            fontSize = 12.sp,
                                            fontWeight = FontWeight.Bold,
                                            modifier = Modifier.journalPress { deleteAction = { model.deleteExam(nearest.id) } },
                                        )
                                    }
                                }
                                Row(
                                    modifier = Modifier.fillMaxWidth().padding(top = 10.dp),
                                    horizontalArrangement = Arrangement.SpaceBetween,
                                    verticalAlignment = Alignment.CenterVertically,
                                ) {
                                    Column(modifier = Modifier.weight(1f)) {
                                        Text(
                                            text = nearest.courseName,
                                            color = palette.ink,
                                            fontSize = 20.sp,
                                            fontWeight = FontWeight.Black,
                                        )
                                        Text(
                                            text = nearestTimeLine,
                                            color = palette.ink.copy(alpha = 0.70f),
                                            fontSize = 12.5.sp,
                                            fontWeight = FontWeight.SemiBold,
                                            modifier = Modifier.padding(top = 4.dp),
                                        )
                                    }
                                    Column(horizontalAlignment = Alignment.End) {
                                        Text(
                                            text = totalHours?.let { "${it / 24L}" } ?: if (nearestOngoing) "考试中" else "—",
                                            color = orangeInk,
                                            fontSize = if (totalHours != null) 40.sp else 22.sp,
                                            fontWeight = FontWeight.Black,
                                            letterSpacing = (-1.5).sp,
                                        )
                                        Text(
                                            text = totalHours?.let { "天 ${it % 24L} 小时" } ?: if (nearestOngoing) "祝顺利" else "时间待定",
                                            color = orangeInk,
                                            fontSize = 11.5.sp,
                                            fontWeight = FontWeight.Bold,
                                        )
                                    }
                                }
                            }
                        }

                    }

                    // 待考在前（标题「接下来」），已结束的单独列在「已结束」下，不再混进待考。
                    val pendingCount = examBuckets.laterPending.size
                    val listedExams = examBuckets.laterPending + examBuckets.past
                    if (listedExams.isNotEmpty()) {
                        val fallbackColors = listOf("orange", "purple", "green", "blue", "pink", "sage")
                        listedExams.forEachIndexed { idx, exam ->
                            val isPast = idx >= pendingCount
                            if (idx == 0 || idx == pendingCount) {
                                Text(
                                    text = if (isPast) "已结束" else "接下来",
                                    color = palette.ink,
                                    fontSize = 15.sp,
                                    fontWeight = FontWeight.Bold,
                                    modifier = Modifier.padding(top = 4.dp),
                                )
                            }
                            val matchedCourse = model.document.courses.firstOrNull {
                                exam.courseName.contains(it.name, ignoreCase = true) || it.name.contains(exam.courseName, ignoreCase = true)
                            }
                            val colorID = matchedCourse?.colorID ?: fallbackColors[idx % fallbackColors.size]
                            val cInk = palette.courseInk(colorID)
                            val inst = CivilStamp.instant(exam.startISO, model.calendar)
                            val z = inst?.atZone(model.calendar.zone)
                            val dCount = ExamTimeline.daysUntilStart(inst?.toEpochMilli(), now)
                            val trailingTop = when {
                                isPast -> "已结束"
                                dCount != null -> "$dCount"
                                exam in examBuckets.ongoing -> "考试中"
                                else -> "—"
                            }
                            val subText = if (z != null) {
                                ExamCopy.upcomingLine(z.monthValue, z.dayOfMonth, z.hour, z.minute, exam.location)
                            } else {
                                "${exam.startISO} · ${ExamCopy.locationLabel(exam.location)}"
                            }

                            SwipeRevealItem(
                                key = exam.id,
                                onEdit = { editingExam = exam; showExam = true },
                                onDelete = { deleteAction = { model.deleteExam(exam.id) } },
                            ) {
                                FrostedCard(
                                    modifier = Modifier.fillMaxWidth(),
                                    cornerRadius = 18.dp,
                                    tier = model.tier,
                                    contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 14.dp, vertical = 12.dp),
                                    onClick = { editingExam = exam; showExam = true },
                                ) {
                                    Row(
                                        modifier = Modifier.fillMaxWidth(),
                                        verticalAlignment = Alignment.CenterVertically,
                                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                                    ) {
                                        CourseGlyphTile(
                                            name = exam.courseName,
                                            colorID = colorID,
                                            size = 44.dp,
                                            cornerRadius = 14.dp,
                                            fontSize = 18.sp,
                                        )
                                        Column(modifier = Modifier.weight(1f)) {
                                            Text(
                                                text = exam.courseName,
                                                color = palette.ink,
                                                fontSize = 15.5.sp,
                                                fontWeight = FontWeight.Black,
                                            )
                                            Text(
                                                text = subText,
                                                color = palette.secondary,
                                                fontSize = 12.sp,
                                                modifier = Modifier.padding(top = 2.dp),
                                            )
                                        }
                                        Column(horizontalAlignment = Alignment.End) {
                                            Text(
                                                text = trailingTop,
                                                color = if (isPast) palette.secondary else cInk,
                                                fontSize = if (dCount != null && !isPast) 22.sp else 14.sp,
                                                fontWeight = FontWeight.Black,
                                            )
                                            if (dCount != null && !isPast) {
                                                Text(
                                                    text = "天",
                                                    color = palette.secondary,
                                                    fontSize = 11.sp,
                                                    fontWeight = FontWeight.Bold,
                                                )
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Text(
                        text = "左滑卡片可编辑或删除考试，点右上角 + 添加新考试。",
                        color = palette.secondary,
                        fontSize = 11.5.sp,
                        modifier = Modifier.padding(start = 4.dp),
                    )
                }
            }

            1 -> {
                // Homework Segment
                if (model.document.homework.isEmpty()) {
                    FrostedCard(modifier = Modifier.fillMaxWidth(), cornerRadius = 20.dp, tier = model.tier) {
                        Text("暂无作业，先添加一项截止任务。", color = palette.secondary, fontSize = 13.5.sp)
                        TextButton(onClick = { editingWork = null; showWork = true }) {
                            Text("添加作业", fontWeight = FontWeight.Bold)
                        }
                    }
                } else {
                    model.document.homework.sortedWith(compareBy<com.classday.app.core.HomeworkTask> { it.done }.thenBy { it.dueISO }).forEach { task ->
                        val dueMillis = CivilStamp.instant(task.dueISO, model.calendar)?.toEpochMilli()
                        SwipeRevealItem(
                            key = task.id,
                            onEdit = { editingWork = task; showWork = true },
                            onDelete = { deleteAction = { model.deleteHomework(task.id) } },
                        ) {
                            FrostedCard(
                                modifier = Modifier.fillMaxWidth(),
                                cornerRadius = 18.dp,
                                tier = model.tier,
                                contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 14.dp, vertical = 12.dp),
                            ) {
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                                ) {
                                    Box(
                                        modifier = Modifier
                                            .size(22.dp)
                                            .journalPress { model.toggleHomework(task.id) }
                                            .clip(androidx.compose.foundation.shape.CircleShape)
                                            .background(
                                                if (task.done) palette.accent else Color.Transparent,
                                                androidx.compose.foundation.shape.CircleShape,
                                            )
                                            .border(2.dp, palette.accent, androidx.compose.foundation.shape.CircleShape),
                                        contentAlignment = Alignment.Center,
                                    ) {
                                        if (task.done) {
                                            Text("✓", color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.Black)
                                        }
                                    }
                                    Column(
                                        modifier = Modifier.weight(1f).clickable { editingWork = task; showWork = true },
                                    ) {
                                        Text(
                                            text = (if (task.done) "已完成 · " else "") + task.title,
                                            color = if (task.done) palette.secondary else palette.ink,
                                            fontSize = 15.sp,
                                            fontWeight = FontWeight.Bold,
                                        )
                                        Text(
                                            text = "${task.courseName.ifBlank { "未关联课程" }} · ${task.dueISO.replace('T', ' ')}",
                                            color = palette.secondary,
                                            fontSize = 12.sp,
                                            modifier = Modifier.padding(top = 2.dp),
                                        )
                                    }
                                    if (dueMillis != null && !task.done) {
                                        StatusPill(
                                            text = CountdownCopy.remaining(dueMillis, now),
                                            containerColor = palette.hero,
                                            contentColor = palette.accentInk,
                                        )
                                    }
                                }
                                Row(
                                    modifier = Modifier.fillMaxWidth().padding(top = 4.dp),
                                    horizontalArrangement = Arrangement.End,
                                ) {
                                    TextButton(onClick = { model.toggleHomework(task.id) }) {
                                        Text(if (task.done) "标记未完成" else "标记完成", fontSize = 12.sp)
                                    }
                                    TextButton(onClick = { editingWork = task; showWork = true }) {
                                        Text("编辑", fontSize = 12.sp)
                                    }
                                    TextButton(onClick = { deleteAction = { model.deleteHomework(task.id) } }) {
                                        Text("删除", color = Color(0xFFFF3B30), fontSize = 12.sp)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            else -> {
                // Grades & Prediction Segment
                FrostedCard(
                    modifier = Modifier.fillMaxWidth(),
                    cornerRadius = 20.dp,
                    tier = model.tier,
                ) {
                    Text("成绩与期末预测", color = palette.ink, fontSize = 16.sp, fontWeight = FontWeight.Black)
                    Text(
                        text = "选择已有评分规则的课程，录入分项成绩后试算目标。导入、分享和课表库统一到「我的 → 数据」。",
                        color = palette.secondary,
                        fontSize = 12.5.sp,
                        modifier = Modifier.padding(top = 4.dp, bottom = 10.dp),
                    )
                    Button(onClick = { model.open(Screen.StudyGrades) }) {
                        Text("期末成绩预测", fontWeight = FontWeight.Bold)
                    }
                }
                val schemeCourses = model.document.courses.filter { it.gradeScheme != null || it.grade != null }
                schemeCourses.forEach { course ->
                    FrostedCard(
                        modifier = Modifier.fillMaxWidth(),
                        cornerRadius = 18.dp,
                        tier = model.tier,
                        onClick = { model.open(Screen.GradePrediction(course.id)) },
                    ) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.SpaceBetween,
                        ) {
                            Row(
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(12.dp),
                            ) {
                                CourseGlyphTile(
                                    name = course.name,
                                    colorID = course.colorID,
                                    size = 42.dp,
                                    cornerRadius = 14.dp,
                                    fontSize = 18.sp,
                                )
                                Column {
                                    Text(course.name, color = palette.ink, fontSize = 15.sp, fontWeight = FontWeight.Black)
                                    Text(
                                        text = if (course.gradeScheme != null) "支持期末目标分数试算" else "已记录总评成绩",
                                        color = palette.secondary,
                                        fontSize = 12.sp,
                                    )
                                }
                            }
                            Text(
                                text = course.grade?.let { "%.1f".format(it) } ?: "试算 ›",
                                color = palette.accent,
                                fontSize = 15.sp,
                                fontWeight = FontWeight.Black,
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun SwipeRevealItem(
    key: Any,
    onEdit: () -> Unit,
    onDelete: () -> Unit,
    content: @Composable () -> Unit,
) {
    var revealed by remember(key) { mutableStateOf(false) }
    var dragSum by remember(key) { mutableStateOf(0f) }
    val actionWidth = 132.dp
    val shiftDp = if (revealed) (-actionWidth) else 0.dp

    Box(
        modifier = Modifier
            .fillMaxWidth()
            .pointerInput(key) {
                detectHorizontalDragGestures(
                    onDragStart = { dragSum = 0f },
                    onDragEnd = {
                        if (dragSum < -40f) revealed = true
                        else if (dragSum > 30f) revealed = false
                        dragSum = 0f
                    },
                ) { _, amount ->
                    dragSum += amount
                }
            },
    ) {
        if (revealed) {
            Row(
                modifier = Modifier
                    .align(Alignment.CenterEnd)
                    .padding(end = 4.dp),
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box(
                    modifier = Modifier
                        .clip(RoundedCornerShape(14.dp))
                        .background(Color(0xFF3A6BFF), RoundedCornerShape(14.dp))
                        .clickable {
                            revealed = false
                            onEdit()
                        }
                        .padding(horizontal = 14.dp, vertical = 12.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Text("编辑", color = Color.White, fontSize = 13.sp, fontWeight = FontWeight.Bold)
                }
                Box(
                    modifier = Modifier
                        .clip(RoundedCornerShape(14.dp))
                        .background(Color(0xFFFF3B30), RoundedCornerShape(14.dp))
                        .clickable {
                            revealed = false
                            onDelete()
                        }
                        .padding(horizontal = 14.dp, vertical = 12.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Text("删除", color = Color.White, fontSize = 13.sp, fontWeight = FontWeight.Bold)
                }
            }
        }
        Box(modifier = Modifier.fillMaxWidth().offset(x = shiftDp)) {
            content()
        }
    }
}

@Composable
private fun ExamForm(existing: com.classday.app.core.ExamEvent?, onCancel: () -> Unit,
                     onSave: (String, String, String, String) -> Boolean) {
    var saveError by remember(existing?.id) { mutableStateOf(false) }
    var name by remember(existing?.id) { mutableStateOf(existing?.courseName.orEmpty()) }
    var start by remember(existing?.id) { mutableStateOf(existing?.startISO ?: java.time.LocalDateTime.now().withSecond(0).withNano(0).toString()) }
    var end by remember(existing?.id) { mutableStateOf(existing?.endISO ?: java.time.LocalDateTime.now().plusHours(1).withSecond(0).withNano(0).toString()) }
    var place by remember(existing?.id) { mutableStateOf(existing?.location.orEmpty()) }
    Field("课程", name) { name = it }
    Field("开始 yyyy-MM-ddTHH:mm", start) { start = it }
    Field("结束 yyyy-MM-ddTHH:mm", end) { end = it }
    Field("地点", place) { place = it }
    if (saveError) Text("未保存，请核对课程名与起止时间，或检查存储状态后重试。内容仍保留。", color = MaterialTheme.colorScheme.error, fontSize = 12.sp)
    Button(onClick = { saveError = !onSave(name, start, end, place) }) { Text("保存考试") }
    TextButton(onClick = onCancel) { Text("取消编辑") }
}

@Composable
private fun WorkForm(existing: com.classday.app.core.HomeworkTask?, onCancel: () -> Unit,
                     onSave: (String, String, String) -> Boolean) {
    var saveError by remember(existing?.id) { mutableStateOf(false) }
    var course by remember(existing?.id) { mutableStateOf(existing?.courseName.orEmpty()) }
    var title by remember(existing?.id) { mutableStateOf(existing?.title.orEmpty()) }
    var due by remember(existing?.id) { mutableStateOf(existing?.dueISO ?: java.time.LocalDateTime.now().plusDays(1).withHour(23).withMinute(59).withSecond(0).withNano(0).toString()) }
    Field("课程（可空）", course) { course = it }
    Field("作业标题", title) { title = it }
    Field("截止 yyyy-MM-ddTHH:mm", due) { due = it }
    if (saveError) Text("未保存，请核对标题与截止时间，或检查存储状态后重试。内容仍保留。", color = MaterialTheme.colorScheme.error, fontSize = 12.sp)
    Button(onClick = { saveError = !onSave(course, title, due) }) { Text("保存作业") }
    TextButton(onClick = onCancel) { Text("取消编辑") }
}

@Composable
private fun StudyGradesPage(model: ClassdayModel) {
    val courses = model.document.courses.filter { it.gradeScheme != null }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        PageTitle("期末成绩预测", model::back)
        Text("选择已有评分规则的课程，保存分项成绩后试算期末所需分数。不会替你修改期末成绩。")
        if (courses.isEmpty()) Text("暂无含评分规则的课程。可到数据页导入包含评分规则的课曜数据；Android 当前只编辑已有规则的分项成绩。", color = rememberIosPalette().secondary)
        courses.forEach { course -> Button(onClick = { model.open(Screen.GradePrediction(course.id)) }) { Text(course.name) } }
    }
}

@Composable
private fun GradePredictionPage(model: ClassdayModel, courseId: String) {
    val course = model.document.courses.firstOrNull { it.id == courseId }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        PageTitle(course?.name ?: "课程已不存在", model::back)
          if (course == null) {
              Text("课程已删除")
              return@Column
          }
          GradeSchemeEditor(initial = course.gradeScheme ?: defaultScheme()) { scheme ->
              model.saveGradeScheme(courseId, scheme)
          }
          course.gradeScheme?.let { scheme ->
              Text("期末目标试算", fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 12.dp))
              FinalScorePanel(scheme) { entries -> model.saveGradeScores(courseId, entries) }
          }
    }
}

@Composable
private fun SettingsHome(model: ClassdayModel) {
    val palette = rememberIosPalette()
    val semester = model.document.semester
    val courseCount = model.document.courses.size
    val weeklyPeriods = model.document.courses.sumOf { c ->
        c.meetings.sumOf { (it.endPeriod - it.startPeriod + 1).coerceAtLeast(1) }
    }
    val currentWeek = model.calendar.weekIndex(LocalDate.now(model.calendar.zone), semester) ?: 1

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 16.dp)
            .padding(top = 8.dp, bottom = 110.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(
            text = "我的",
            color = palette.ink,
            fontSize = 27.sp,
            fontWeight = FontWeight.Black,
            letterSpacing = (-0.5).sp,
        )

        // Top Semester Overview Card
        FrostedCard(
            modifier = Modifier.fillMaxWidth(),
            cornerRadius = 22.dp,
            tier = model.tier,
            contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
            onClick = { model.open(Screen.SemesterEdit) },
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(14.dp),
            ) {
                val tileShape = RoundedCornerShape(18.dp)
                Box(
                    modifier = Modifier
                        .size(54.dp)
                        .clip(tileShape)
                        .background(
                            brush = androidx.compose.ui.graphics.Brush.linearGradient(
                                colors = listOf(Color(0xFF3A6BFF), Color(0xFF6C8CFF)),
                            ),
                            shape = tileShape,
                        ),
                    contentAlignment = Alignment.Center,
                ) {
                    Text("课", color = Color.White, fontSize = 24.sp, fontWeight = FontWeight.Black)
                }
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = semester.shortName.ifBlank { semester.name },
                        color = palette.ink,
                        fontSize = 17.sp,
                        fontWeight = FontWeight.Black,
                    )
                    Text(
                        text = "$courseCount 门课 · 每周 $weeklyPeriods 节 · 第 $currentWeek / ${semester.totalWeeks} 周",
                        color = palette.secondary,
                        fontSize = 12.5.sp,
                        fontWeight = FontWeight.SemiBold,
                        modifier = Modifier.padding(top = 3.dp),
                    )
                }
                Text("›", color = palette.secondary, fontSize = 18.sp, fontWeight = FontWeight.Bold)
            }
        }

        // 外观 Group
        SettingsGroupSection(title = "外观", tier = model.tier) {
            MeSettingsRow(
                icon = "🎨",
                iconBg = palette.courseBg("purple"),
                title = "主题与性能",
                value = model.theme.name,
                showDivider = false,
                onClick = { model.open(Screen.Appearance) },
            )
        }

        // 课表 Group
        SettingsGroupSection(title = "课表", tier = model.tier) {
            MeSettingsRow(
                icon = "⏱",
                iconBg = palette.courseBg("blue"),
                title = "上课时间",
                value = "${semester.periods.size} 节",
                onClick = { model.open(Screen.Periods) },
            )
            MeSettingsRow(
                icon = "📅",
                iconBg = palette.courseBg("green"),
                title = "学期",
                value = "${semester.totalWeeks} 周",
                onClick = { model.open(Screen.SemesterEdit) },
            )
            MeSettingsRow(
                icon = "🏖",
                iconBg = palette.courseBg("orange"),
                title = "假期与不上课时段",
                value = if (semester.holidays.isNotEmpty()) "${semester.holidays.size} 项" else "",
                showDivider = false,
                onClick = { model.open(Screen.Holidays) },
            )
        }

        // 通用 Group
        SettingsGroupSection(title = "通用", tier = model.tier) {
            MeSettingsRow(
                icon = "🔔",
                iconBg = palette.courseBg("orange"),
                title = "提醒",
                value = "提前 ${semester.defaultReminderMinutes} 分钟",
                onClick = {
                    model.ensureReminderDraft()
                    model.open(Screen.Reminders)
                },
            )
            MeSettingsRow(
                icon = "💾",
                iconBg = palette.courseBg("blue"),
                title = "数据",
                value = "导入 / 导出",
                onClick = { model.open(Screen.DataPage) },
            )
            MeSettingsRow(
                icon = "🏫",
                iconBg = palette.courseBg("green"),
                title = "教室位置",
                value = roomSummary(model),
                onClick = { model.open(Screen.RoomLocations) },
            )
            MeSettingsRow(
                icon = "ℹ️",
                iconBg = palette.elevated,
                title = "关于",
                value = "v${com.classday.app.BuildConfig.VERSION_NAME}",
                showDivider = false,
                onClick = { model.open(Screen.About) },
            )
        }
    }
}

@Composable
private fun SettingsGroupSection(
    title: String,
    tier: PerformanceTier,
    content: @Composable androidx.compose.foundation.layout.ColumnScope.() -> Unit,
) {
    val palette = rememberIosPalette()
    Column(modifier = Modifier.fillMaxWidth()) {
        Text(
            text = title,
            color = palette.secondary,
            fontSize = 12.sp,
            fontWeight = FontWeight.Bold,
            modifier = Modifier.padding(start = 6.dp, bottom = 6.dp),
        )
        FrostedCard(
            modifier = Modifier.fillMaxWidth(),
            cornerRadius = 20.dp,
            tier = tier,
            contentPadding = androidx.compose.foundation.layout.PaddingValues(vertical = 2.dp),
            content = content,
        )
    }
}

@Composable
private fun MeSettingsRow(
    icon: String,
    iconBg: Color,
    title: String,
    value: String = "",
    showDivider: Boolean = true,
    onClick: () -> Unit,
) {
    val palette = rememberIosPalette()
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .journalPress(scaleDown = 0.98f, onClick = onClick),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Box(
                modifier = Modifier
                    .size(32.dp)
                    .clip(RoundedCornerShape(10.dp))
                    .background(iconBg, RoundedCornerShape(10.dp)),
                contentAlignment = Alignment.Center,
            ) {
                Text(text = icon, fontSize = 16.sp)
            }
            Text(
                text = title,
                color = palette.ink,
                fontSize = 15.sp,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.weight(1f),
            )
            if (value.isNotBlank()) {
                Text(
                    text = value,
                    color = palette.secondary,
                    fontSize = 13.sp,
                    fontWeight = FontWeight.Medium,
                )
            }
            Text(
                text = "›",
                color = palette.secondary,
                fontSize = 16.sp,
                fontWeight = FontWeight.Bold,
            )
        }
        if (showDivider) {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(start = 60.dp, end = 16.dp)
                    .height(1.dp)
                    .background(palette.line),
            )
        }
    }
}

@Composable
private fun AppearancePage(model: ClassdayModel) {
    val theme = model.theme
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp)) {
        PageTitle("主题与性能", model::back)
        Text(theme.englishName + " · " + theme.tagline, color = rememberIosPalette().secondary)
        Text("外观", fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 12.dp))
        // 8 套主题铺成两列，全部一眼可见（原来是横向滚动，右边几套看不到）。
        ClassdayThemes.all.chunked(2).forEach { row ->
            Row(Modifier.fillMaxWidth().padding(top = 6.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                row.forEach { item ->
                    val selected = theme.id == item.id
                    Surface(
                        onClick = { model.setTheme(item.id) },
                        shape = RoundedCornerShape(16.dp),
                        color = if (selected) rememberIosPalette().accent.copy(alpha = 0.18f) else rememberIosPalette().elevated,
                        border = androidx.compose.foundation.BorderStroke(
                            width = if (selected) 1.5.dp else 1.dp,
                            color = if (selected) rememberIosPalette().accent else rememberIosPalette().line,
                        ),
                        modifier = Modifier.weight(1f),
                    ) {
                        Column(Modifier.padding(horizontal = 14.dp, vertical = 12.dp)) {
                            Text(item.name, fontWeight = FontWeight.Bold, fontSize = 14.sp, color = rememberIosPalette().ink)
                            Text(item.englishName, fontSize = 11.sp, color = rememberIosPalette().secondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        }
                    }
                }
                if (row.size == 1) Spacer(Modifier.weight(1f))
            }
        }
        Button(onClick = { model.cycleTheme() }, modifier = Modifier.padding(top = 8.dp).semantics { contentDescription = "换一套" }) { Text("换一套") }
        Row(Modifier.padding(top = 8.dp)) {
            PerformanceTier.entries.forEach { tier ->
                FilterChip(selected = model.document.appearance.performance == tier, onClick = { model.setTier(tier) }, label = { Text(tier.title) }, modifier = Modifier.padding(end = 6.dp))
            }
        }
        Text(model.tier.detail, color = rememberIosPalette().secondary, fontSize = 12.sp)
    }
}

@Composable
private fun SettingsCard(title: String, content: @Composable () -> Unit) {
    Card(Modifier.fillMaxWidth().padding(top = 12.dp), colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface.copy(alpha = 0.9f))) {
        Column(Modifier.padding(8.dp)) {
            Text(title, fontWeight = FontWeight.Bold, modifier = Modifier.padding(8.dp))
            content()
        }
    }
}

@Composable
private fun SettingsRow(title: String, onClick: () -> Unit) {
    Text(title, modifier = Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 12.dp, vertical = 14.dp))
}

@Composable
private fun PeriodsPage(model: ClassdayModel) {
    var periods by remember { mutableStateOf(model.document.semester.periods) }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp)) {
        PageTitle("上课时间", model::back)
        periods.forEachIndexed { index, period ->
            Column(Modifier.padding(vertical = 2.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("第 ${period.index} 节", modifier = Modifier.width(54.dp))
                    OutlinedTextField(period.start, { value -> periods = periods.mapIndexed { i, item -> if (i == index) item.copy(start = value) else item } }, modifier = Modifier.weight(1f), label = { Text("开始") }, singleLine = true)
                    Spacer(Modifier.width(6.dp))
                    OutlinedTextField(period.end, { value -> periods = periods.mapIndexed { i, item -> if (i == index) item.copy(end = value) else item } }, modifier = Modifier.weight(1f), label = { Text("结束") }, singleLine = true)
                    Spacer(Modifier.width(2.dp))
                    TextButton(onClick = {
                        periods = periods
                            .filterIndexed { i, _ -> i != index }
                            .mapIndexed { i, item -> item.copy(index = i + 1) }
                    }) { Text("删除", color = Color(0xFFB3261E), fontSize = 12.sp) }
                }
            }
        }
        TextButton(onClick = {
            val last = periods.lastOrNull()
            val start = last?.end?.let { com.classday.app.core.ScheduleTextImporter.addMinutesToClock(it, 10) } ?: "08:00"
            val end = com.classday.app.core.ScheduleTextImporter.addMinutesToClock(start, 45) ?: "08:45"
            periods = periods + com.classday.app.core.PeriodTemplate(periods.size + 1, start, end)
        }) { Text("＋ 添加一节", fontWeight = FontWeight.Bold) }
        Button(onClick = { model.saveSemester(model.document.semester.copy(periods = periods)) }, modifier = Modifier.padding(top = 12.dp)) { Text("保存") }
        Text("删除节次后，后面的节次会顺延编号；已排的课按节次编号对应，请保存后核对课表。", color = rememberIosPalette().secondary, fontSize = 12.sp, modifier = Modifier.padding(top = 8.dp))
    }
}

/** 「我的 → 教室位置」右侧的摘要：已校准 x / 共 y。 */
/** 全部教室名：课程地点 + 每次课自己的教室，合并串按 " / " 拆开。 */
private fun allRoomNames(model: ClassdayModel): List<String> {
    val raw = buildList {
        model.document.courses.forEach { course ->
            add(course.location)
            course.meetings.forEach { add(it.location) }
        }
    }
    return raw
        .flatMap { it.split(" / ", "/") }
        .map { it.trim() }
        .filter { it.isNotEmpty() && it != "—" }
        .distinct()
        .sorted()
}

private fun roomSummary(model: ClassdayModel): String {
    val rooms = allRoomNames(model)
    if (rooms.isEmpty()) return "暂无教室"
    val calibrated = rooms.count { name ->
        com.classday.app.core.MapLinks.hasPreciseQuery(name, model.document.rooms.firstOrNull { it.name == name })
    }
    return "已校准 $calibrated / ${rooms.size}"
}

@Composable
private fun RoomLocationsPage(model: ClassdayModel) {
    val context = LocalContext.current
    val palette = rememberIosPalette()
    val rooms = allRoomNames(model)
    val lastChoice = Maps.lastChoice(context)
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp)) {
        PageTitle("教室位置", model::back)
        Text(
            "给每间教室绑定一次地图关键词（楼名 + 房间号），导航就能直接搜到。未校准的教室只能按名字模糊搜索。",
            fontSize = 13.sp,
            color = palette.secondary,
            modifier = Modifier.padding(bottom = 12.dp),
        )
        for ((index, name) in rooms.withIndex()) {
            val pin = model.document.rooms.firstOrNull { it.name == name }
            val calibrated = com.classday.app.core.MapLinks.hasPreciseQuery(name, pin)
            Row(
                modifier = Modifier.fillMaxWidth().padding(vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(if (calibrated) "✅" else "🎯", fontSize = 16.sp)
                Spacer(Modifier.width(10.dp))
                Column(Modifier.weight(1f)) {
                    Text(name, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = palette.ink)
                    Text(
                        if (calibrated) pin?.query.orEmpty() else "未校准 · 点右侧填写关键词",
                        fontSize = 12.sp,
                        color = palette.secondary,
                    )
                }
                TextButton(onClick = {
                    Maps.promptRoomQuery(context, name, pin) { model.bindRoomQuery(name, it) }
                }) { Text(if (calibrated) "修改" else "校准") }
            }
            if (index != rooms.lastIndex) {
                Box(Modifier.fillMaxWidth().height(1.dp).background(palette.line))
            }
        }
        if (rooms.isEmpty()) {
            Text("还没有课程教室，先添加课程。", fontSize = 13.sp, color = palette.secondary)
        }
        Spacer(Modifier.height(20.dp))
        Text("导航偏好", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = palette.ink)
        Text(
            lastChoice?.let { "上次使用：$it" } ?: "还没选过地图，下次导航时会让你选。",
            fontSize = 13.sp,
            color = palette.secondary,
            modifier = Modifier.padding(top = 4.dp, bottom = 8.dp),
        )
        TextButton(onClick = {
            Maps.resetRememberedChoice(context)
            model.banner = "已清除记住的地图"
        }) { Text("清除记住的地图") }
    }
}
@Composable
private fun SemesterPage(model: ClassdayModel) {
    val initial = model.semesterDraft ?: model.document.semester
    var name by remember { mutableStateOf(initial.name) }
    var short by remember { mutableStateOf(initial.shortName) }
    var start by remember { mutableStateOf(initial.startDate) }
    var weeks by remember { mutableStateOf(initial.totalWeeks.toString()) }
    val draftSemester = model.document.semester.copy(name = name, shortName = short, startDate = start, totalWeeks = weeks.toIntOrNull() ?: initial.totalWeeks)
    LaunchedEffect(name, short, start, weeks) { model.semesterDraft = draftSemester }
    val end = model.calendar.endDate(draftSemester)
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp)) {
        PageTitle("学期", model::back)
        Field("名称", name) { name = it }
        Field("简称", short) { short = it }
        Field("开始日期", start) { start = it }
        Field("周数", weeks) { weeks = it }
        Text("结束日期 ${end?.let(model.calendar::formatCivil) ?: "—"}", modifier = Modifier.padding(top = 8.dp))
        Button(onClick = { model.saveSemester(draftSemester) }, modifier = Modifier.padding(top = 12.dp)) { Text("保存") }
    }
}

@Composable
private fun HolidayPage(model: ClassdayModel) {
    var name by remember { mutableStateOf("") }
    var start by remember { mutableStateOf("") }
    var end by remember { mutableStateOf("") }
    val context = LocalContext.current
    val ics = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        val text = context.contentResolver.openInputStream(uri)?.bufferedReader()?.readText().orEmpty()
        val holidays = HolidayImporter.parseIcs(text, model.calendar)
        model.saveSemester(model.document.semester.copy(holidays = model.document.semester.holidays + holidays))
    }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp)) {
        PageTitle("假期与不上课时段", model::back)
        model.document.semester.holidays.forEach { holiday ->
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text("${holiday.name}  ${holiday.startDate}–${holiday.endDate}", modifier = Modifier.weight(1f))
                TextButton(onClick = { model.saveSemester(model.document.semester.copy(holidays = model.document.semester.holidays.filter { it.id != holiday.id })) }) { Text("删除") }
            }
        }
        Field("假期名称", name) { name = it }
        Field("开始", start) { start = it }
        Field("结束", end) { end = it }
        Button(onClick = {
            if (name.isBlank() || model.calendar.parseCivil(start) == null) return@Button
            val holiday = HolidayPeriod(newId(), name, start, end.ifBlank { start })
            model.saveSemester(model.document.semester.copy(holidays = model.document.semester.holidays + holiday))
            name = ""; start = ""; end = ""
        }) { Text("添加假期") }
        TextButton(onClick = { ics.launch(arrayOf("text/*", "application/octet-stream")) }) { Text("从 .ics 校历导入") }
        CancellationSection(model)
    }
}

/** 停课：手动增删改 + 粘贴通知/拍照识别。列表每条都能编辑后再保存。 */
@Composable
private fun CancellationSection(model: ClassdayModel) {
    val palette = rememberIosPalette()
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var editing by remember { mutableStateOf<ClassCancellation?>(null) }
    var notice by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    val entries = model.document.semester.cancellations

    fun save(entry: ClassCancellation) {
        val rest = entries.filter { it.id != entry.id }
        model.saveSemester(model.document.semester.copy(cancellations = rest + entry))
        model.banner = "已保存停课安排"
    }

    val photo = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        busy = true
        scope.launch {
            val text = runCatching { com.classday.app.platform.OcrReader.read(context, uri) }.getOrDefault("")
            busy = false
            if (text.isBlank()) {
                model.banner = "这张图没识别出文字"
            } else {
                notice = text
                val parsed = com.classday.app.core.CancellationParser.parse(text, model.document.courses)
                if (parsed.isEmpty()) model.banner = "没认出日期或课程，可手动添加"
                else editing = parsed.first()
            }
        }
    }

    Text("停课", fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 16.dp))
    if (entries.isEmpty()) {
        Text("还没有停课安排。可以粘贴通知文字、拍照识别，或手动添加。", color = palette.secondary, fontSize = 12.sp)
    }
    entries.forEach { entry ->
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                "${entry.date.ifEmpty { "未定日期" }} · ${entry.courseName.ifEmpty { "当天全部" }} · ${entry.reason}",
                modifier = Modifier.weight(1f),
                fontSize = 13.sp,
            )
            TextButton(onClick = { editing = entry }) { Text("编辑") }
            TextButton(onClick = {
                model.saveSemester(model.document.semester.copy(cancellations = entries.filter { it.id != entry.id }))
            }) { Text("恢复", color = Color(0xFFB3261E)) }
        }
    }
    OutlinedTextField(
        value = notice,
        onValueChange = { notice = it },
        label = { Text("粘贴停课通知文字（例如：11 月 20 日 高等数学 停课）") },
        modifier = Modifier.fillMaxWidth().padding(top = 6.dp),
        minLines = 2,
    )
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        TextButton(enabled = !busy, onClick = {
            val parsed = com.classday.app.core.CancellationParser.parse(notice, model.document.courses)
            if (parsed.isEmpty()) model.banner = "没认出日期或课程，可手动添加" else editing = parsed.first()
        }) { Text("识别文字") }
        TextButton(enabled = !busy, onClick = { photo.launch(arrayOf("image/*")) }) {
            Text(if (busy) "识别中…" else "拍照/选图识别")
        }
        TextButton(onClick = {
            editing = ClassCancellation(newId(), "", null, "", "all", "")
        }) { Text("＋ 手动添加") }
    }

    val current = editing
    if (current != null) {
        var date by remember(current.id) { mutableStateOf(current.date) }
        var courseName by remember(current.id) { mutableStateOf(current.courseName) }
        var reason by remember(current.id) { mutableStateOf(current.reason) }
        AlertDialog(
            onDismissRequest = { editing = null },
            title = { Text(if (current.date.isBlank() && current.courseName.isBlank()) "添加停课" else "编辑停课") },
            text = {
                Column {
                    OutlinedTextField(date, { date = it }, label = { Text("日期 yyyy-MM-dd") }, singleLine = true)
                    OutlinedTextField(courseName, { courseName = it }, label = { Text("课程名（留空=当天全部）") }, singleLine = true)
                    OutlinedTextField(reason, { reason = it }, label = { Text("原因") }, singleLine = true)
                    if (model.document.courses.isNotEmpty()) {
                        Text("快速选择课程", fontSize = 12.sp, color = palette.secondary, modifier = Modifier.padding(top = 6.dp))
                        androidx.compose.foundation.layout.FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            model.document.courses.take(12).forEach { course ->
                                FilterChip(selected = courseName == course.name, onClick = { courseName = course.name }, label = { Text(course.name, fontSize = 11.sp) })
                            }
                        }
                    }
                }
            },
            confirmButton = {
                TextButton(onClick = {
                    val matched = model.document.courses.firstOrNull { it.name == courseName }
                    save(
                        current.copy(
                            date = date.trim(),
                            courseID = matched?.id,
                            courseName = courseName.trim(),
                            scope = if (courseName.isBlank()) "all" else "course",
                            reason = reason.trim(),
                        ),
                    )
                    editing = null
                }) { Text("保存") }
            },
            dismissButton = { TextButton(onClick = { editing = null }) { Text("取消") } },
        )
    }
}
@Composable
private fun ReminderPage(model: ClassdayModel) {
    model.ensureReminderDraft()
    var minutes by remember { mutableStateOf((model.reminderDraft ?: model.document.semester.defaultReminderMinutes).toString()) }
    val context = LocalContext.current
    var confirmDnd by remember { mutableStateOf(false) }
    var dndStatus by remember { mutableStateOf(com.classday.app.platform.ClassroomDnd.status(context)) }
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    LaunchedEffect(lifecycle) {
        lifecycle.repeatOnLifecycle(Lifecycle.State.RESUMED) {
            com.classday.app.platform.ClassroomDnd.sync(context)
            dndStatus = com.classday.app.platform.ClassroomDnd.status(context)
        }
    }
    if (confirmDnd) {
        AlertDialog(onDismissRequest = { confirmDnd = false },
            title = { Text("同意课表上课时使用勿扰？") },
            text = { Text("默认不开启。授权并启用后，课曜会在真实课表的上课时段请求优先通知勿扰，下课仅撤销课曜自己的请求；系统允许哪些来电和通知由你的勿扰设置决定。需要勿扰访问和精确定时授权；可随时停用。") },
            confirmButton = { TextButton(onClick = {
                confirmDnd = false
                dndStatus = com.classday.app.platform.ClassroomDnd.setConsent(context, true)
            }) { Text("我同意，启用上课勿扰") } },
            dismissButton = { TextButton(onClick = { confirmDnd = false }) { Text("暂不开启") } })
    }
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp)) {
        PageTitle("提醒", model::back)
        Field("默认提前分钟", minutes) { minutes = it; model.reminderDraft = it.toIntOrNull() }
        Text("离开这一页也会留着还没保存的数字。", color = rememberIosPalette().secondary, fontSize = 12.sp)
        Button(onClick = {
            if (android.os.Build.VERSION.SDK_INT >= 33) permission.launch(Manifest.permission.POST_NOTIFICATIONS)
            model.saveReminderDraft()
        }, modifier = Modifier.padding(top = 12.dp)) { Text("保存") }
        if (android.os.Build.VERSION.SDK_INT >= 31) {
            TextButton(onClick = {
                try {
                    context.startActivity(Intent(android.provider.Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
                        data = Uri.parse("package:${context.packageName}")
                    })
                } catch (_: Exception) { model.banner = "无法打开精确定时授权页，请到系统设置中允许课曜的闹钟和提醒" }
            }) { Text("在系统中允许精确定时") }
        }
        Text("上课勿扰（可选）", fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 16.dp))
        Text(dndStatus, fontSize = 12.sp)
        Text("Android 10 或以上可用。仅对真实课表生效，演示数据不触发；假期/停课/调课沿用课表。系统或厂商节电可能延后后台执行，请核对通知栏勿扰状态。", fontSize = 12.sp)
        TextButton(onClick = {
            try { context.startActivity(Intent(android.provider.Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS)) }
            catch (_: Exception) { model.banner = "无法打开勿扰授权页，请到系统设置中找到课曜的勿扰访问" }
        }) { Text("在系统中允许勿扰访问") }
        Button(enabled = com.classday.app.platform.ClassroomDnd.supported(), onClick = { confirmDnd = true }) { Text("启用上课勿扰…") }
        TextButton(onClick = { dndStatus = com.classday.app.platform.ClassroomDnd.setConsent(context, false) }) { Text("停用课曜上课勿扰") }
        Text("停用课曜不会关闭你手动开启或其他应用开启的勿扰。未授权或不启用时，应用内上课专注仍自动可用。", fontSize = 12.sp)
    }
}

@Composable
private fun DataPage(model: ClassdayModel) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var showImport by rememberSaveable { mutableStateOf(false) }
    var importSummary by remember { mutableStateOf("") }
    var confirmImport by remember { mutableStateOf<(() -> Unit)?>(null) }
    if (confirmImport != null) {
        AlertDialog(onDismissRequest = { confirmImport = null },
            title = { Text("确认导入数据？") }, text = { Text(importSummary) },
            confirmButton = { TextButton(onClick = {
                val action = confirmImport
                confirmImport = null
                action?.invoke()
            }) { Text("确认导入") } },
            dismissButton = { TextButton(onClick = { confirmImport = null }) { Text("取消") } })
    }
    var icsUrl by remember { mutableStateOf(model.document.subscribedICSURL) }
    var libraryName by remember { mutableStateOf("") }
    var showMail by remember { mutableStateOf(false) }
    var mailText by remember { mutableStateOf("") }
    val export = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/json")) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        context.contentResolver.openOutputStream(uri)?.use { it.write(model.exportJson().toByteArray()) }
        model.banner = "已导出数据"
    }
    val importJson = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        try {
            val text = context.contentResolver.openInputStream(uri)?.bufferedReader()?.use { it.readText() }
                ?: error("无法读取文件")
            if (text.contains("BEGIN:VCALENDAR")) {
                val parsed = ICSImporter.parse(text, model.calendar, model.document.semester.totalWeeks, model.document.semester.periods)
                importSummary = "将追加 ${parsed.courses.size} 门课程、${parsed.exams.size} 场考试、${parsed.homework.size} 项作业。确认后才写入。" + "\n" + parsed.warnings.joinToString("\n")
                confirmImport = { model.importCalendar(parsed.courses, parsed.exams, parsed.homework) }
            } else {
                val outcome = StoreCodec.importing(text, model.calendar)
                val imported = outcome.document
                if (imported == null) model.banner = outcome.errors.firstOrNull() ?: "无法解析数据"
                else {
                    importSummary = "将替换当前课表：${imported.courses.size} 门课程、${imported.exams.size} 场考试、${imported.homework.size} 项作业。建议先导出备份。\n" + outcome.warnings.joinToString("\n")
                    confirmImport = { model.importDocument(text, replace = true) }
                }
            }
        } catch (_: Exception) { model.banner = "无法读取数据，请重新选择本机 JSON 或 ICS 文件" }
    }

    val importCsv = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        scope.launch {
            val text = withContext(Dispatchers.IO) {
                try {
                    context.contentResolver.openInputStream(uri)?.bufferedReader(Charsets.UTF_8)?.use { it.readText() }
                } catch (_: Exception) { null }
            }
            if (text == null) model.banner = "无法读取文件，请重新选择 UTF-8 CSV"
            else model.stageDrafts(text, csv = true)
        }
    }
    var pdfBusy by remember { mutableStateOf(false) }
    val importPdf = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri == null || pdfBusy) return@rememberLauncherForActivityResult
        scope.launch {
            pdfBusy = true
            try {
                val parsed = com.classday.app.platform.PdfScheduleReader.read(context, uri)
                model.stageDraftImport(parsed)
            } catch (cancelled: kotlinx.coroutines.CancellationException) {
                throw cancelled
            } catch (_: Exception) {
                model.banner = "PDF 未导入：请选择本机未加密、1–10 页且不超过 8 MB 的 PDF；云盘文件请先下载。扫描件或图片页要清晰，复杂表格可改用 Excel/CSV 导入。"
            } finally {
                pdfBusy = false
            }
        }
    }
    val importExcel = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        scope.launch {
            val result = withContext(Dispatchers.IO) {
                runCatching {
                    val input = context.contentResolver.openInputStream(uri) ?: error("无法读取所选文件")
                    input.use { com.classday.app.core.ExcelScheduleImporter.parse(it) }
                }
            }
            result.onSuccess { model.stageDraftImport(it) }.onFailure {
                model.banner = "Excel 导入失败：请用单工作表 .xlsx，取消合并单元格、将公式粘贴为值，时间存为文本；或另存为 CSV UTF-8 导入。"
            }
        }
    }
    val importWord = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        scope.launch {
            val result = withContext(Dispatchers.IO) {
                runCatching {
                    val input = context.contentResolver.openInputStream(uri) ?: error("无法读取所选文件")
                    input.use { com.classday.app.core.WordScheduleImporter.parse(it) }
                }
            }
            result.onSuccess { model.stageDraftImport(it) }
                .onFailure { model.banner = "Word 导入失败：请确认是未加密的 .docx，文件小于 8 MB，正文或表格包含课程名、星期和时间/节次。" }
        }
    }
    var captureName by rememberSaveable { mutableStateOf<String?>(null) }
    var captureBusy by remember { mutableStateOf(false) }
    var recognizingName by remember { mutableStateOf<String?>(null) }
    val captureDirectory = java.io.File(context.filesDir, "classday-camera")
    LaunchedEffect(Unit) {
        val active = listOfNotNull(captureName, recognizingName).toSet()
        withContext(Dispatchers.IO) {
            com.classday.app.core.CameraCaptureFiles.removeExpired(captureDirectory, active, System.currentTimeMillis())
        }
    }
    val camera = rememberLauncherForActivityResult(ActivityResultContracts.TakePicture()) { success ->
        val name = captureName
        val file = com.classday.app.core.CameraCaptureFiles.resolve(captureDirectory, name)
        captureName = null
        if (!success || file == null) {
            com.classday.app.core.CameraCaptureFiles.remove(captureDirectory, name)
            if (!success) model.banner = "已取消拍照，课表未改变"
        } else {
            captureBusy = true
            recognizingName = name
            scope.launch {
                try {
                    require(com.classday.app.core.CameraCaptureFiles.readablePhoto(file))
                    val uri = androidx.core.content.FileProvider.getUriForFile(context, "${context.packageName}.files", file)
                    val text = OcrReader.read(context, uri)
                    model.stageDrafts(text, mail = true)
                } catch (cancelled: kotlinx.coroutines.CancellationException) {
                    throw cancelled
                } catch (_: Exception) {
                    model.banner = "照片没读出来：请重拍清晰、光线充足的课表，或从相册换一张；超过 16 MB 的照片也会失败。"
                } finally {
                    com.classday.app.core.CameraCaptureFiles.remove(captureDirectory, name)
                    captureBusy = false
                    recognizingName = null
                }
            }
        }
    }
    fun launchCamera() {
        try {
            val file = com.classday.app.core.CameraCaptureFiles.create(captureDirectory)
            captureName = file.name
            val uri = androidx.core.content.FileProvider.getUriForFile(context, "${context.packageName}.files", file)
            camera.launch(uri)
        } catch (_: Exception) {
            com.classday.app.core.CameraCaptureFiles.remove(captureDirectory, captureName)
            captureName = null
            model.banner = "未能打开相机，请从相册选择课表图片"
        }
    }
    val cameraPermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) launchCamera() else model.banner = "未授权相机，仍可从相册识别课表图片"
    }
    val photo = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        scope.launch {
            val text = try {
                OcrReader.read(context, uri)
            } catch (_: Exception) {
                model.banner = "没有认出文字"
                return@launch
            }
            model.stageDrafts(text)
        }
    }
    val calendarPermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { granted ->
        if (granted.values.all { it }) model.banner = CalendarSync.sync(context, model.document)
        else model.banner = "需要日历权限才能写入"
    }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        PageTitle("数据", model::back)
        Text("导出与分享", fontWeight = FontWeight.Bold, color = rememberIosPalette().secondary, fontSize = 12.sp)
        Button(onClick = { export.launch("classday-${model.document.semester.shortName}.json") }) { Text("导出数据") }
        Button(onClick = { showImport = !showImport }) { Text(if (showImport) "收起导入数据" else "导入数据") }
        if (showImport) {
            Text("导入", fontWeight = FontWeight.Bold, color = rememberIosPalette().secondary, fontSize = 12.sp)
        Text("都在本机处理，核对预览后才写入课表。", color = rememberIosPalette().secondary, fontSize = 12.sp)
            TextButton(onClick = { showMail = !showMail }) { Text(if (showMail) "收起" else "粘贴文字识别") }
            if (showMail) {
    
                OutlinedTextField(mailText, { mailText = it.take(100_000) }, label = { Text("邮件课表正文") },
                    modifier = Modifier.fillMaxWidth(), minLines = 3, maxLines = 8)
    
                Button(enabled = mailText.isNotBlank(), onClick = { model.stageDrafts(mailText, mail = true) }) { Text("识别并预览") }
            }
            Button(onClick = { importJson.launch(arrayOf("application/json", "text/*", "application/octet-stream")) }) { Text("备份文件（JSON / ICS）") }
            Button(onClick = { importCsv.launch(arrayOf("text/*", "application/csv", "application/vnd.ms-excel", "application/octet-stream")) }) { Text("CSV 表格") }
            Button(onClick = { importExcel.launch(arrayOf("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")) }) { Text("Excel（.xlsx）") }
    
            Button(onClick = { importWord.launch(arrayOf("application/vnd.openxmlformats-officedocument.wordprocessingml.document")) }) { Text("Word（.docx）") }
    
            Button(enabled = !pdfBusy, onClick = { importPdf.launch(arrayOf("application/pdf")) }) { Text(if (pdfBusy) "正在识别 PDF…" else "PDF（本机识别）") }
    
    
            OutlinedTextField(icsUrl, { icsUrl = it }, label = { Text("iCal 日历地址（本次读取）") }, modifier = Modifier.fillMaxWidth())
            Button(onClick = {
                scope.launch {
                    val text = withContext(Dispatchers.IO) {
                        try { URL(icsUrl).readText() } catch (_: Exception) { null }
                    }
                    if (text == null) model.banner = "地址无效，粘贴完整的 iCal 订阅地址再试"
                    else {
                        val parsed = ICSImporter.parse(text, model.calendar, model.document.semester.totalWeeks, model.document.semester.periods)
                        val subscription = icsUrl
                        importSummary = "将订阅并追加 ${parsed.courses.size} 门课程、${parsed.exams.size} 场考试、${parsed.homework.size} 项作业。确认后才写入。" + "\n" + parsed.warnings.joinToString("\n")
                        confirmImport = { model.importCalendar(parsed.courses, parsed.exams, parsed.homework, subscription) }
                    }
                }
            }) { Text("读取并预览") }
            Button(enabled = !captureBusy && captureName == null, onClick = {
                if (androidx.core.content.ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == android.content.pm.PackageManager.PERMISSION_GRANTED) launchCamera()
                else cameraPermission.launch(Manifest.permission.CAMERA)
            }) { Text(if (captureBusy) "正在识别照片…" else "拍照识别") }
            Button(onClick = { photo.launch(androidx.activity.result.PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }) { Text("从相册识别") }
    
        }

        if (model.hasDemoCourses()) {
            TextButton(onClick = { model.removeDemoCourses() }) {
                Text("删除案例课程", color = Color(0xFFB3261E), fontWeight = FontWeight.Bold)
            }
            Text(
                "演示用的那几门课（高等数学、大学英语…）会一并删除，自己导入和新建的课不受影响。",
                color = rememberIosPalette().secondary,
                fontSize = 12.sp,
            )
        }
        Button(onClick = {
            calendarPermission.launch(arrayOf(Manifest.permission.READ_CALENDAR, Manifest.permission.WRITE_CALENDAR))
        }) { Text("同步到系统日历") }
        if (model.mergeableGroups().isNotEmpty()) {
            Button(onClick = { model.open(Screen.Merge) }) { Text("${model.mergeableGroups().size} 组可合并同名课程") }
        }
        Text("课表库 · 先命名另存，再点已存课表切换。切换会保留当前课表，课程、考试和作业一起切换；仅存本机。", fontSize = 12.sp)
        OutlinedTextField(libraryName, { libraryName = it }, label = { Text("存入课表库的名字") }, modifier = Modifier.fillMaxWidth())
        Button(onClick = { if (libraryName.isNotBlank()) model.storeLibrary(libraryName) }) { Text("保存当前课表") }
        model.document.library.forEach { stored ->
            TextButton(onClick = { model.switchLibrary(stored.id) }) { Text("切换到 ${stored.name}") }
        }
        TextButton(onClick = { model.clearAll() }) { Text("清空课程") }
    }
}

@Composable
private fun QrImage(text: String) {
    val bitmap = remember(text) {
        try {
            val hints = hashMapOf<com.google.zxing.EncodeHintType, Any>(com.google.zxing.EncodeHintType.MARGIN to 1)
            val matrix = com.google.zxing.qrcode.QRCodeWriter().encode(text.take(1800), com.google.zxing.BarcodeFormat.QR_CODE, 512, 512, hints)
            androidx.compose.ui.graphics.ImageBitmap(matrix.width, matrix.height).also { image ->
                val canvas = androidx.compose.ui.graphics.Canvas(image)
                val paint = androidx.compose.ui.graphics.Paint()
                for (y in 0 until matrix.height) {
                    for (x in 0 until matrix.width) {
                        paint.color = if (matrix.get(x, y)) Color.Black else Color.White
                        canvas.drawRect(androidx.compose.ui.geometry.Rect(x.toFloat(), y.toFloat(), x + 1f, y + 1f), paint)
                    }
                }
            }
        } catch (_: Exception) {
            null
        }
    }
    if (bitmap != null) {
        androidx.compose.foundation.Image(bitmap = bitmap, contentDescription = "课表二维码", modifier = Modifier.size(180.dp).clip(RoundedCornerShape(12.dp)))
    } else {
        Text("二维码装不下整份课表，用上面的链接分享。")
    }
}

@Composable
private fun ImportReviewPage(model: ClassdayModel) {
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp)) {
        PageTitle("确认导入", model::back)
        Text(model.importNote, color = rememberIosPalette().secondary)
        model.importDrafts.forEachIndexed { index, draft ->
            var editing by remember(index) { mutableStateOf(false) }
            Card(Modifier.fillMaxWidth().padding(vertical = 4.dp)) {
                Column(Modifier.padding(12.dp)) {
                    Row(verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                        Text(draft.name, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
                        TextButton(onClick = { editing = !editing }) { Text(if (editing) "完成" else "编辑") }
                        TextButton(onClick = { model.removeDraft(index) }) { Text("删除") }
                    }
                    Text(listOf(draft.teacher, draft.location).filter { it.isNotBlank() }.joinToString(" · "), fontSize = 12.sp)
                    Text("周次：${draft.weeks.joinToString("、")}", fontSize = 12.sp)
                    draft.meetings.forEach { meeting ->
                        val clockText = ScheduleTextImporter.periodClockLabel(meeting.startPeriod, meeting.endPeriod, model.document.semester)
                        Text(
                            listOfNotNull(
                                ScheduleCopy.weekdayName(meeting.weekday),
                                ScheduleTextImporter.periodSpanLabel(meeting.startPeriod, meeting.endPeriod),
                                clockText,
                                meeting.parity.title,
                            ).joinToString(" "),
                            fontSize = 12.sp,
                        )
                    }
                    if (editing) {
                        DraftEditor(
                            model = model,
                            index = index,
                            draft = draft,
                        )
                    }
                }
            }
        }
        Button(onClick = { model.confirmDrafts() }) { Text("写入课表") }
    }
}

/** 识别结果的逐条编辑：改名/教师/教室/周次，星期与节次可逐条改。 */
@Composable
private fun DraftEditor(model: ClassdayModel, index: Int, draft: CourseDraft) {
    Column(Modifier.padding(top = 8.dp)) {
        DraftField("课程名", draft.name) { value -> model.editDraft(index) { it.copy(name = value) } }
        DraftField("教师", draft.teacher) { value -> model.editDraft(index) { it.copy(teacher = value) } }
        DraftField("班级", draft.className) { value -> model.editDraft(index) { it.copy(className = value) } }
        DraftField("教室/地点", draft.location) { value -> model.editDraft(index) { it.copy(location = value) } }
        DraftField("周次（用逗号分隔，例如 1,2,3,9-16）", draft.weeks.joinToString(",")) { value ->
            val weeks = parseWeeksText(value)
            if (weeks.isNotEmpty()) model.editDraft(index) { it.copy(weeks = weeks) }
        }
        draft.meetings.forEachIndexed { meetingIndex, meeting ->
            Text("第 ${meetingIndex + 1} 个时段", fontSize = 12.sp, modifier = Modifier.padding(top = 6.dp))
            androidx.compose.foundation.layout.FlowRow(
                horizontalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(6.dp),
            ) {
                (1..7).forEach { day ->
                    FilterChip(
                        selected = meeting.weekday == day,
                        onClick = {
                            model.editDraft(index) { course ->
                                course.copy(meetings = course.meetings.mapIndexed { i, m ->
                                    if (i == meetingIndex) m.copy(weekday = day) else m
                                })
                            }
                        },
                        label = { Text(ScheduleCopy.weekdayName(day), fontSize = 11.sp) },
                    )
                }
            }
            Row(horizontalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(8.dp)) {
                DraftField("起始节", meeting.startPeriod?.toString().orEmpty(), Modifier.weight(1f)) { value ->
                    val parsed = value.trim().toIntOrNull()
                    model.editDraft(index) { course ->
                        course.copy(meetings = course.meetings.mapIndexed { i, m ->
                            if (i == meetingIndex) m.copy(startPeriod = parsed, explicitPeriod = parsed != null) else m
                        })
                    }
                }
                DraftField("结束节", meeting.endPeriod?.toString().orEmpty(), Modifier.weight(1f)) { value ->
                    val parsed = value.trim().toIntOrNull()
                    model.editDraft(index) { course ->
                        course.copy(meetings = course.meetings.mapIndexed { i, m ->
                            if (i == meetingIndex) m.copy(endPeriod = parsed, explicitPeriod = parsed != null) else m
                        })
                    }
                }
            }
        }
    }
}

@Composable
private fun DraftField(
    label: String,
    value: String,
    modifier: Modifier = Modifier.fillMaxWidth(),
    onChange: (String) -> Unit,
) {
    var text by remember(value) { mutableStateOf(value) }
    OutlinedTextField(
        value = text,
        onValueChange = { text = it; onChange(it) },
        label = { Text(label, fontSize = 12.sp) },
        singleLine = true,
        modifier = modifier.padding(vertical = 2.dp),
    )
}

/** 「1,2,3,9-16」这种写法展开成周次列表。 */
private fun parseWeeksText(raw: String): List<Int> {
    val weeks = mutableSetOf<Int>()
    raw.split(',', '，', '、', ' ', ';').map { it.trim() }.filter { it.isNotEmpty() }.forEach { part ->
        val range = Regex("""^(\d{1,2})\s*[-~—–]\s*(\d{1,2})$""").find(part)
        if (range != null) {
            val from = range.groupValues[1].toIntOrNull() ?: return@forEach
            val to = range.groupValues[2].toIntOrNull() ?: return@forEach
            if (from in 1..30 && to in from..30) weeks += (from..to)
        } else {
            part.toIntOrNull()?.let { if (it in 1..30) weeks += it }
        }
    }
    return weeks.sorted()
}
/** 全部课程：与 iOS 的「课程」页一致，按名字排序，点进去是课程详情。 */
@Composable
private fun CourseListSection(model: ClassdayModel, palette: IosPalette) {
    var query by rememberSaveable { mutableStateOf("") }
    val currentWeek = model.weekIndex()
    val allCourses = model.document.courses
    // 已结束的课程（所有周次都在当前周之前）不再出现在列表里。
    val activeCourses = allCourses.filter { (it.weeks.maxOrNull() ?: 0) >= currentWeek }
    val courses = activeCourses
        .filter { query.isBlank() || it.name.contains(query, ignoreCase = true) || it.teacher.contains(query, ignoreCase = true) }
        .sortedBy { it.name }
    if (allCourses.isEmpty()) {
        FrostedCard(modifier = Modifier.fillMaxWidth(), cornerRadius = 20.dp, tier = model.tier) {
            Text("还没有课程，可到「我的 → 数据」导入，或在课表页新建。", color = palette.secondary, fontSize = 13.5.sp)
        }
        return
    }
    OutlinedTextField(
        value = query,
        onValueChange = { query = it },
        label = { Text("搜索课程 / 教师", fontSize = 12.sp) },
        singleLine = true,
        modifier = Modifier.fillMaxWidth(),
    )
    Text("共 ${activeCourses.size} 门", color = palette.secondary, fontSize = 12.sp)
    courses.forEach { course ->
        FrostedCard(modifier = Modifier.fillMaxWidth(), cornerRadius = 18.dp, tier = model.tier) {
            Row(
                Modifier
                    .fillMaxWidth()
                    .journalPress {
                        model.open(Screen.Detail(course.id, null, model.weekIndex()))
                    }
                    .padding(horizontal = 14.dp, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                CourseGlyphTile(name = course.name, colorID = course.colorID, size = 46.dp)
                Column(Modifier.weight(1f).padding(start = 12.dp)) {
                    Text(course.name, color = palette.ink, fontSize = 15.5.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    val room = course.location.trim().ifEmpty {
                        course.meetings.map { it.location.trim() }.filter { it.isNotBlank() }.distinct().joinToString(" / ")
                    }
                    if (room.isNotBlank()) {
                        Text(room, color = palette.secondary, fontSize = 12.5.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                }
                val next = model.nextOccurrenceFor(course.id)
                Column(horizontalAlignment = Alignment.End, modifier = Modifier.padding(start = 8.dp)) {
                    Text("下一次", color = palette.secondary, fontSize = 11.sp)
                    if (next != null) {
                        val zone = model.calendar.zone
                        val when_ = java.time.Instant.ofEpochMilli(next.startEpochMillis).atZone(zone)
                        val date = when_.toLocalDate()
                        val today = java.time.LocalDate.now(zone)
                        val clock = "%02d:%02d".format(when_.hour, when_.minute)
                        val label = when {
                            date == today -> "今天 $clock"
                            date == today.plusDays(1) -> "明天 $clock"
                            else -> "${ScheduleCopy.weekdayName(next.weekday)} $clock"
                        }
                        Text(label, color = palette.accent, fontSize = 13.sp, fontWeight = FontWeight.Bold)
                    }
                }
                Text("›", color = palette.secondary, fontSize = 20.sp, modifier = Modifier.padding(start = 6.dp))
            }
        }
    }
    if (courses.isEmpty()) {
        Text("没有匹配的课程", color = palette.secondary, fontSize = 13.sp)
    }
}
@Composable
private fun MergePage(model: ClassdayModel) {
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp)) {
        PageTitle("合并同名课程", model::back)
        Text("合并前会先把当前课表存进课表库。仅合并周次、教室及同一时段单双周规则兼容的课程。", color = rememberIosPalette().secondary)
        model.duplicates().forEach { group ->
            var chosen by remember(group.normalizedName) { mutableStateOf<String?>(null) }
            var excluded by remember(group.normalizedName) { mutableStateOf(setOf<String>()) }
            val selected = com.classday.app.core.selectedMergeGroup(group, excluded)
            Card(Modifier.fillMaxWidth().padding(vertical = 6.dp)) {
                Column(Modifier.padding(12.dp)) {
                    Text(group.courses.first().name, fontWeight = FontWeight.Bold)
                    group.courses.forEach { course ->
                        FilterChip(
                            selected = course.id !in excluded,
                            onClick = { excluded = if (course.id in excluded) excluded - course.id else excluded + course.id },
                            label = { Text("${if (course.id in excluded) "已排除" else "参与合并"} · ${course.teacher} · ${course.location} · ${course.weeks.joinToString(",")}周") }
                        )
                    }
                    if (gradeConflict(selected)) {
                        Text("成绩不一样，请先选择要保留的成绩")
                        selected.courses.filter { it.grade != null }.forEach { course ->
                            FilterChip(selected = chosen == course.id, onClick = { chosen = course.id }, label = { Text("${course.grade}") }, modifier = Modifier.padding(end = 6.dp))
                        }
                    }
                    val compatible = selected.courses.size >= 2 && com.classday.app.core.canMergeCourseSchedules(selected.courses, model.document)
                    if (!compatible) Text("请保留至少两门排课兼容的课程；可排除周次、教室或单双周不同的成员。", color = rememberIosPalette().secondary)
                    Button(enabled = com.classday.app.core.canSubmitCourseMerge(selected, chosen, model.document), onClick = { model.merge(selected, chosen) }) { Text("合并所选课程") }
                }
            }
        }
    }
}

@Composable
private fun AboutPage(model: ClassdayModel) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var status by remember { mutableStateOf("尚未检查更新") }
    var checking by remember { mutableStateOf(false) }
    var showLog by remember { mutableStateOf(false) }
    if (showLog) {
        AlertDialog(onDismissRequest = { showLog = false }, title = { Text("更新日志 · ${com.classday.app.BuildConfig.VERSION_NAME}") },
            text = { Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("2.10.5：成绩录入改版——不再有「候选算法」「权重合计」这些看不懂的词。现在按老师的评分说明填四段：① 选 20/100 分制；② 评分项填「得分 + 占比(%) + 最低分」，占比直接写 25 就是 25%；③ 需要「补考 / 期末替代期中」时再加一条方案，新方案自动照抄第一条，多条取最高；④ 结果区显示总成绩、折合百分制、绩点，并提醒哪一项低于最低分要求。默认模板直接给「小组项目 25% / 期中测验 25% / 期末考试 50%」。", fontSize = 12.sp)
                Text("2.10.4：课程页改为「全部课程 / 考试 / 作业 / 成绩」，全部课程按 iOS 样式显示（首字头像、教室、下一次上课时间、箭头）；课程列表只显示教室，不再堆时段与周次。识别或导入后可以逐条编辑课程名、教师、教室、周次、星期与节次，也能删掉认错的那条；PDF 课表按版面还原成节次×星期，实测一份教务课表从 0 门变 10 门。修好切主题没反应、浅色主题卡片发白、背景不跟主题走的问题；主题改为两列铺开，8 套一屏看全。数据页删掉大段说明与分享链接；上课时间可增删节次；新增停课：可粘贴通知、拍照识别，也能手动增删改。", fontSize = 12.sp)
                Text("2.10.3：我的 › 教室位置——一页看全所有教室的校准状态（已校准 x / 共 y），逐个校准或修改关键词；导航会记住上次用的地图 App，下次直接跳转不弹选择框，想换回弹框在「教室位置」里清除即可。")
                Text("2.10.2：教室导航大修——给每间教室绑定一次地图关键词（楼名+房间号），导航直接用这个关键词搜，不再拿「Room PA1」满世界乱找；未校准的教室在课程详情里有显眼提示，点一下就能校准，保存后长期生效；已绑定时地图菜单直接给步行路线。")
                Text("2.10.1：修好同名课合并的两个真 bug——名字结尾带空格或孤立括号（如「Power Conversion & Storage   (   」）现在也能并成一门；只有一个成员填了教室时不再把教室弄丢。AI 识别改用内置密钥，界面上不再出现任何密钥输入框或提示文字。")
                Text("2.10.0：教室下沉到单次课——同一门课分在不同教室时，周视图与今日列表里每一次课显示自己那间教室（周一 Room AM、周三 Room FA3），不再是一串合并后的全教室；同名课仍自动合并，课程卡片保留全部教室清单；课表格式升到 schemaVersion 2，旧课表打开自动迁移。")
                Text("2.9.9：同名课程合并改成只看课程名——不同教室、不同周次的同名课也直接并成一门，教室全部显示在课程卡片上（例如「Room C9 / Room V1.17」），周次与时段取并集；此前要求教室和周次完全一致，讲座与实验因此被拆成好几门。")
                Text("2.9.8：同名课程自动合并——打开应用或导入之后，同名的课只要周次、教室和单双周能对上就直接并成一门（周次与时段取并集），不再需要先确认；成绩不同的按较高分保留，考试、作业、停课与单次调课都跟着合并后的课程走；只有安排真的冲突才留到合并页手动处理。")
                Text("2.9.7：安装包从 60.5 MB 降到约 22 MB——去掉只为模拟器编译的两种 CPU 架构、开启代码与资源裁剪、换掉整套图标库，并移除已下线登录用到的两个库，功能不减少。补上每节课的「提前 N 分钟」提醒：此前这个设置只改按钮文案，实际按课程边界加固定 1 小时预闹钟；现在按每门课的提前量各自排点，设为 0 就是这门课不提醒，考试与作业按学期默认提前量提醒，点提醒直接进对应页面。清理已下线的 Fénix 登录与 iCloud 残留代码。")
                Text("2.9.6：Android 界面全面焕新为通透磨砂卡片与悬浮胶囊底栏；今日页升级下一节课主角卡、今日进度环与时间线；课表页新增七日胶囊条、午晚餐虚线分隔与左右滑切周，修复跨日或残留周偏移导致的周数差一；课程详情改为半高可上拉底部弹窗，支持一键导航、编辑、提醒和加作业；学习页精简为考试、作业、成绩三段切换并支持左滑操作，去掉虚构复习进度条；我的页顶置学期总览卡并按外观、课表、通用分组；移除安卓语音查课表入口。修复考场名含 % 等符号时考试页崩溃、已结束考试顶替最近一场倒计时、课表日期条点选本周其他日期无反应，以及深色模式下部分页面文字对比不足；导入时源节次在本学期不存在会说明改按时间导入。")
                Text("2.9.5：统一数据导入及预览确认，数据页不再提供恢复演示数据入口；学习页集中考试、作业和成绩预测；考试和作业都能编辑，填错会提示并保留内容；应用内上课专注与可选授权勿扰；更新来源改用公开清单，更新包核对体积与校验值，校验或安装启动失败会提示；教室导航可选系统地图、已安装的高德或百度，没有坐标就按名称搜索。")
                Text("此前版本：今日首页、侧载小组件读取回退、期末预测和录分，拍照/邮件/Excel/Word/PDF 本机识别与确认导入、普通周课表拖拽。")
            } }, confirmButton = { TextButton(onClick = { showLog = false }) { Text("关闭") } })
    }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        PageTitle("关于", model::back)
        Text("课曜 / Heptara", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Black)
        Text("版本 ${com.classday.app.BuildConfig.VERSION_NAME}")
        Text("课曜把课程、教室与每周安排保存在本机，提供小组件、图片与文件导入、考试作业管理、期末成绩预测和教室地图导航。支持上课提醒与应用内上课专注。导入先核对，再确认保存。")
        Text("系统勿扰需要你明确同意及授权。", fontSize = 12.sp)
        Button(onClick = { showLog = true }) { Text("更新日志") }
        Text(status)
        Button(enabled = !checking, onClick = {
            scope.launch {
                checking = true
                status = "正在检查更新…"
                try { status = withContext(Dispatchers.IO) { com.classday.app.platform.UpdateClient.check(context) } }
                catch (_: Exception) { status = "更新检查未完成，请稍后重试" }
                finally { checking = false }
            }
        }) { Text(if (checking) "检查中…" else "检查更新") }
    }
}
