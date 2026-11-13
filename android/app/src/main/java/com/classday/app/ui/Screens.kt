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
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
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
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.classday.app.core.CivilStamp
import com.classday.app.core.ClassdayThemes
import com.classday.app.core.CountdownCopy
import com.classday.app.core.Course
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
import com.classday.app.platform.FenixAuth
import com.classday.app.platform.FenixConfig
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
    val theme = model.theme
    val motion = model.tier != PerformanceTier.saver && theme.usesMotion
    val tilt = rememberTilt(motion)
    val scheme = if (theme.prefersDark) {
        androidx.compose.material3.darkColorScheme(
            primary = theme.accent(),
            onPrimary = theme.bg(),
            background = Color.Transparent,
            surface = theme.card(),
            onBackground = theme.ink(),
            onSurface = theme.ink(),
            secondary = theme.glow(),
            outline = theme.line(),
        )
    } else {
        androidx.compose.material3.lightColorScheme(
            primary = theme.accent(),
            onPrimary = Color.White,
            background = Color.Transparent,
            surface = theme.card(),
            onBackground = theme.ink(),
            onSurface = theme.ink(),
            secondary = theme.glow(),
            outline = theme.line(),
        )
    }
    MaterialTheme(colorScheme = scheme) {
        Box(Modifier.fillMaxSize()) {
            ThemeBackdrop(theme, model.tier, tilt)
            Scaffold(
                containerColor = Color.Transparent,
                bottomBar = {
                    if (model.screen is Screen.Week || model.screen is Screen.Countdown || model.screen is Screen.Settings) {
                        NavigationBar(containerColor = theme.card().copy(alpha = 0.92f)) {
                            NavigationBarItem(selected = model.screen is Screen.Week, onClick = { model.goHome(Screen.Week) }, icon = { Text("课") }, label = { Text("课表") })
                            NavigationBarItem(selected = model.screen is Screen.Countdown, onClick = { model.goHome(Screen.Countdown) }, icon = { Text("计") }, label = { Text("倒计时") })
                            NavigationBarItem(selected = model.screen is Screen.Settings, onClick = { model.goHome(Screen.Settings) }, icon = { Text("我") }, label = { Text("我的") })
                        }
                    }
                },
            ) { padding ->
                Box(Modifier.padding(padding).fillMaxSize()) {
                    when (val screen = model.screen) {
                        Screen.Week -> WeekPage(model, tilt)
                        Screen.Countdown -> CountdownPage(model)
                        Screen.Settings -> SettingsHome(model)
                        Screen.Periods -> PeriodsPage(model)
                        Screen.SemesterEdit -> SemesterPage(model)
                        Screen.Holidays -> HolidayPage(model)
                        Screen.Reminders -> ReminderPage(model)
                        Screen.DataPage -> DataPage(model)
                        Screen.About -> AboutPage(model)
                        Screen.ImportReview -> ImportReviewPage(model)
                        Screen.Merge -> MergePage(model)
                        is Screen.Detail -> DetailPage(model, screen)
                        is Screen.Editor -> EditorPage(model, screen.courseId)
                    }
                }
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
private fun WeekPage(model: ClassdayModel, tilt: Offset) {
    val theme = model.theme
    val week = model.weekIndex()
    val items = model.occurrences()
    val now = System.currentTimeMillis()
    val next = ScheduleEngine.next(Instant.ofEpochMilli(now), model.document.courses, model.document.semester, model.calendar, model.document.scheduleContext)
    val current = ScheduleEngine.current(Instant.ofEpochMilli(now), model.document.courses, model.document.semester, model.calendar, model.document.scheduleContext)
    Column(Modifier.fillMaxSize()) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text("课曜", color = theme.secondary(), fontSize = 12.sp)
                Text("第 $week 周", color = theme.ink(), fontSize = 28.sp, fontWeight = FontWeight.Black)
                Text(model.calendar.weekRangeLabel(week, model.document.semester), color = theme.secondary(), fontFamily = FontFamily.Monospace)
            }
            Column(horizontalAlignment = Alignment.End) {
                TextButton(onClick = { model.cycleTheme() }, modifier = Modifier.semantics { contentDescription = "换一套" }) {
                    Text(theme.name, color = theme.accent())
                }
                Text(model.tier.title, color = theme.secondary(), fontSize = 11.sp)
            }
        }
        if (model.document.origin == com.classday.app.core.DataOrigin.demo) {
            Text("演示数据", color = theme.accent(), modifier = Modifier.padding(horizontal = 16.dp), fontSize = 12.sp)
        }
        val focus = current ?: next
        if (focus != null) {
            val until = if (current != null) focus.endEpochMillis else focus.startEpochMillis
            Text(
                "${if (current != null) "上课中" else "下一节"} · ${focus.name} · ${CountdownCopy.remaining(until, now)}",
                color = theme.ink(),
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
            )
        }
        Row(Modifier.padding(horizontal = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = { model.shiftWeek(-1) }) { Text("上一周") }
            TextButton(onClick = { model.backToThisWeek() }) { Text("回本周") }
            TextButton(onClick = { model.shiftWeek(1) }) { Text("下一周") }
        }
        val holiday = model.calendar.holiday(java.time.ZonedDateTime.now(model.calendar.zone), model.document.semester)
        if (holiday != null) Text("假期 · ${holiday.name}", color = theme.accent(), modifier = Modifier.padding(horizontal = 16.dp))
        Box(Modifier.weight(1f).fillMaxWidth().padding(8.dp)) {
            when {
                theme.usesOrbit -> OrbitBoard(model, items, week)
                theme.usesCube -> CubeBoard(model, items)
                else -> WeekGrid(model, items, week, tilt)
            }
        }
    }
}

@Composable
private fun WeekGrid(model: ClassdayModel, items: List<Occurrence>, week: Int, tilt: Offset) {
    val theme = model.theme
    val periods = model.document.semester.periods.size.coerceAtLeast(1)
    val rowHeight = if (theme.specialLayout == "mech") 48.dp else 44.dp
    val todayWeek = model.calendar.weekIndex(LocalDate.now(model.calendar.zone), model.document.semester)
    val today = LocalDate.now(model.calendar.zone).dayOfWeek.value
    Column(Modifier.verticalScroll(rememberScrollState()).padding(bottom = 24.dp).offset(x = tilt.x.dp / 4, y = tilt.y.dp / 4)) {
        Row {
            Spacer(Modifier.width(28.dp))
            (1..7).forEach { day ->
                Text(
                    ScheduleCopy.weekdayShort(day),
                    modifier = Modifier.weight(1f),
                    color = if (day == today && week == todayWeek) theme.accent() else theme.secondary(),
                    fontSize = 12.sp,
                )
            }
        }
        Box(Modifier.fillMaxWidth().height(rowHeight * periods)) {
            if (theme.specialLayout == "hud") Canvas(Modifier.fillMaxSize()) { hudTicks(theme.glow()) }
            Column {
                repeat(periods) { index ->
                    Row(Modifier.height(rowHeight), verticalAlignment = Alignment.CenterVertically) {
                        Text("${index + 1}", color = theme.secondary(), modifier = Modifier.width(28.dp), fontSize = 10.sp, fontFamily = FontFamily.Monospace)
                        Box(Modifier.weight(1f).height(1.dp).background(theme.line().copy(alpha = 0.4f)))
                    }
                }
            }
            Row(Modifier.fillMaxSize().padding(start = 28.dp)) {
                (1..7).forEach { day ->
                    Box(Modifier.weight(1f).fillMaxSize().padding(1.dp)) {
                        items.filter { it.weekday == day }.forEach { item ->
                            val span = (item.endPeriod - item.startPeriod + 1).coerceAtLeast(1)
                            val accent = theme.courseAccent(item.colorID)
                            val shape = if (theme.specialLayout == "mech") RoundedCornerShape(4.dp) else RoundedCornerShape(10.dp)
                            Column(
                                Modifier
                                    .padding(top = rowHeight * (item.startPeriod - 1))
                                    .height(rowHeight * span)
                                    .fillMaxWidth()
                                    .clip(shape)
                                    .background(rgb(accent.r, accent.g, accent.b, if (theme.prefersDark) 0.9f else 0.82f))
                                    .border(1.dp, theme.glow().copy(alpha = if (theme.specialLayout == "neon") 0.95f else 0.3f), shape)
                                    .clickable { model.open(Screen.Detail(item.courseID, item.meetingID, week)) }
                                    .semantics { contentDescription = "${item.name} ${ScheduleCopy.weekdayName(item.weekday)} ${item.timeText} ${item.parityLabel}" }
                                    .padding(3.dp),
                            ) {
                                Text(item.name, color = Color.White, fontWeight = FontWeight.Bold, fontSize = 10.sp, maxLines = 3)
                                Text(item.timeText, color = Color.White.copy(alpha = 0.85f), fontSize = 8.sp, maxLines = 1)
                                if (item.parityLabel.isNotEmpty()) Text(item.parityLabel, color = Color.White, fontSize = 8.sp)
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun OrbitBoard(model: ClassdayModel, items: List<Occurrence>, week: Int) {
    val theme = model.theme
    val today = LocalDate.now(model.calendar.zone).dayOfWeek.value
    Canvas(Modifier.fillMaxSize().clickable { }) {
        val center = Offset(size.width / 2f, size.height / 2f)
        drawCircle(theme.line().copy(alpha = 0.5f), radius = size.minDimension * 0.18f, center = center, style = androidx.compose.ui.graphics.drawscope.Stroke(2f))
        drawCircle(theme.line().copy(alpha = 0.35f), radius = size.minDimension * 0.34f, center = center, style = androidx.compose.ui.graphics.drawscope.Stroke(1.5f))
        items.forEachIndexed { index, item ->
            val angle = (item.weekday - 1) / 7f * 6.28318f - 1.5708f + item.startPeriod * 0.08f
            val radius = size.minDimension * (0.18f + (item.startPeriod / 14f))
            val point = Offset(center.x + cos(angle).toFloat() * radius, center.y + sin(angle).toFloat() * radius)
            val accent = theme.courseAccent(item.colorID)
            drawCircle(rgb(accent.r, accent.g, accent.b), radius = if (item.weekday == today) 16f else 11f, center = point)
        }
    }
    Column(Modifier.alignIfPossible().padding(12.dp)) {
        items.take(6).forEach { item ->
            Text("${ScheduleCopy.weekdayShort(item.weekday)} ${item.name}", color = theme.ink(), modifier = Modifier.clickable { model.open(Screen.Detail(item.courseID, item.meetingID, week)) }.padding(vertical = 2.dp))
        }
    }
}

private fun Modifier.alignIfPossible() = this

@Composable
private fun CubeBoard(model: ClassdayModel, items: List<Occurrence>) {
    val theme = model.theme
    var day by remember { mutableIntStateOf(LocalDate.now(model.calendar.zone).dayOfWeek.value) }
    Column(Modifier.fillMaxSize().padding(12.dp)) {
        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            (1..7).forEach { weekday ->
                FilterChip(selected = day == weekday, onClick = { day = weekday; model.haptic("glass") }, label = { Text(ScheduleCopy.weekdayName(weekday)) })
            }
        }
        Spacer(Modifier.height(12.dp))
        Card(
            shape = RoundedCornerShape(28.dp),
            colors = CardDefaults.cardColors(containerColor = theme.card().copy(alpha = 0.72f)),
            modifier = Modifier.fillMaxWidth().weight(1f).border(1.dp, theme.glow().copy(alpha = 0.5f), RoundedCornerShape(28.dp)),
        ) {
            Column(Modifier.padding(16.dp).verticalScroll(rememberScrollState())) {
                Text(ScheduleCopy.weekdayName(day), color = theme.accent(), fontWeight = FontWeight.Bold)
                val dayItems = items.filter { it.weekday == day }
                if (dayItems.isEmpty()) Text("这一天没有课", color = theme.secondary(), modifier = Modifier.padding(top = 12.dp))
                dayItems.forEach { item ->
                    Text("${item.timeText}  ${item.name}", color = theme.ink(), modifier = Modifier.padding(top = 10.dp).clickable { model.open(Screen.Detail(item.courseID, item.meetingID, model.weekIndex())) }, fontWeight = FontWeight.SemiBold)
                    Text(item.location, color = theme.secondary(), fontSize = 12.sp)
                }
            }
        }
        Text("轻点星期，像把玻璃立方转到下一天。", color = theme.secondary(), fontSize = 12.sp, modifier = Modifier.padding(top = 8.dp))
    }
}

@Composable
private fun DetailPage(model: ClassdayModel, screen: Screen.Detail) {
    val theme = model.theme
    val course = model.document.courses.firstOrNull { it.id.equals(screen.courseId, ignoreCase = true) }
    if (course == null) {
        PageTitle("课程", model::back)
        Text("这门课不在当前课表里", modifier = Modifier.padding(16.dp))
        return
    }
    val item = model.occurrences().firstOrNull { it.courseID.equals(course.id, true) && (screen.meetingId == null || it.meetingID.equals(screen.meetingId, true)) }
        ?: ScheduleEngine.occurrences(screen.week, listOf(course), model.document.semester, model.calendar, model.document.scheduleContext).firstOrNull()
    var moveWeekday by remember { mutableIntStateOf(item?.weekday ?: 1) }
    var movePeriod by remember { mutableIntStateOf(item?.startPeriod ?: 1) }
    val context = LocalContext.current
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp)) {
        PageTitle(course.name, model::back)
        Text(course.teacher, color = theme.secondary())
        Text(course.location, color = theme.ink(), modifier = Modifier.padding(top = 4.dp))
        Text("${course.kind} · ${ScheduleCopy.weekList(course.weeks)}", color = theme.secondary(), modifier = Modifier.padding(top = 4.dp))
        item?.let {
            Text("${ScheduleCopy.weekdayName(it.weekday)} ${it.timeText} ${it.parityLabel}", color = theme.accent(), modifier = Modifier.padding(top = 8.dp), fontFamily = FontFamily.Monospace)
        }
        if (course.note.isNotBlank()) Text(course.note, modifier = Modifier.padding(top = 8.dp))
        course.grade?.let { Text("成绩 $it", color = theme.ink(), modifier = Modifier.padding(top = 8.dp)) }
        course.gradeScheme?.normalizedFinal?.let { Text("规则折合 ${"%.1f".format(it)}", color = theme.secondary()) }
        Spacer(Modifier.height(12.dp))
        if (item != null) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(onClick = { model.cancelThisWeek(item) }) { Text("本周停课") }
                Button(onClick = { model.delayThisWeek(item) }) { Text("推迟 10 分钟") }
            }
            Spacer(Modifier.height(8.dp))
            Text("本周调课", fontWeight = FontWeight.Bold)
            Stepper("星期 $moveWeekday", { moveWeekday = (moveWeekday - 1).coerceAtLeast(1) }, { moveWeekday = (moveWeekday + 1).coerceAtMost(7) })
            Stepper("开始节次 $movePeriod", { movePeriod = (movePeriod - 1).coerceAtLeast(1) }, { movePeriod = (movePeriod + 1).coerceAtMost(model.document.semester.periods.size) })
            Button(onClick = { model.moveThisWeek(item, moveWeekday, movePeriod) }) { Text("只改本周") }
            Button(onClick = { model.moveMeeting(item.courseID, item.meetingID, moveWeekday, movePeriod) }) { Text("调整整学期") }
            TextButton(onClick = { model.clearThisWeek(item) }) { Text("恢复本周") }
            Text("单双周", fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 8.dp))
            val parity = model.document.scheduleContext.parity(item.meetingID)
            Row {
                WeekParity.entries.forEach { option ->
                    FilterChip(selected = parity == option, onClick = { model.setParity(item.meetingID, option) }, label = { Text(option.title) }, modifier = Modifier.padding(end = 6.dp))
                }
            }
            Button(onClick = {
                val pin = model.document.rooms.firstOrNull { it.name == course.location }
                context.startActivity(Maps.intent(course.location, pin?.latitude, pin?.longitude).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            }, modifier = Modifier.padding(top = 8.dp)) { Text("导航到教室") }
        }
        Row(Modifier.padding(top = 12.dp)) {
            TextButton(onClick = { model.open(Screen.Editor(course.id)) }) { Text("编辑") }
            TextButton(onClick = { model.deleteCourse(course.id) }) { Text("删除") }
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
private fun CountdownPage(model: ClassdayModel) {
    val now = System.currentTimeMillis()
    var showExam by remember { mutableStateOf(false) }
    var showWork by remember { mutableStateOf(false) }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("倒计时", style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Black, modifier = Modifier.weight(1f))
            IconButton(onClick = { showExam = !showExam }) { Icon(Icons.Default.Add, contentDescription = "添加考试") }
        }
        Text("考试", fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 8.dp))
        if (model.document.exams.isEmpty()) Text("还没有考试。可以从日历或 Fénix 导入。", color = model.theme.secondary())
        model.document.exams.sortedBy { it.startISO }.forEach { exam ->
            val whenMillis = CivilStamp.instant(exam.startISO, model.calendar)?.toEpochMilli()
            Card(Modifier.fillMaxWidth().padding(vertical = 4.dp), colors = CardDefaults.cardColors(containerColor = model.theme.card().copy(alpha = 0.85f))) {
                Column(Modifier.padding(12.dp)) {
                    Text(exam.courseName, fontWeight = FontWeight.Bold)
                    Text(exam.startISO + "  " + exam.location, fontFamily = FontFamily.Monospace, fontSize = 12.sp)
                    if (whenMillis != null) Text(CountdownCopy.remaining(whenMillis, now), color = model.theme.accent())
                    TextButton(onClick = { model.deleteExam(exam.id) }) { Text("删除") }
                }
            }
        }
        if (showExam) ExamForm { name, time, place -> model.addExam(name, time, place); showExam = false }
        Text("作业", fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 12.dp))
        model.document.homework.sortedBy { it.dueISO }.forEach { task ->
            val due = CivilStamp.instant(task.dueISO, model.calendar)?.toEpochMilli()
            Row(Modifier.fillMaxWidth().padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f).clickable { model.toggleHomework(task.id) }) {
                    Text((if (task.done) "已完成 · " else "") + task.title, fontWeight = FontWeight.SemiBold)
                    Text("${task.courseName}  ${task.dueISO}" + if (due != null && !task.done) "  ${CountdownCopy.remaining(due, now)}" else "", fontSize = 12.sp, color = model.theme.secondary())
                }
            }
        }
        TextButton(onClick = { showWork = !showWork }) { Text("添加作业") }
        if (showWork) WorkForm { course, title, due -> model.addHomework(course, title, due); showWork = false }
    }
}

@Composable
private fun ExamForm(onSave: (String, String, String) -> Unit) {
    var name by remember { mutableStateOf("") }
    var time by remember { mutableStateOf("2026-12-22T09:00") }
    var place by remember { mutableStateOf("") }
    Field("课程", name) { name = it }
    Field("开始 yyyy-MM-ddTHH:mm", time) { time = it }
    Field("地点", place) { place = it }
    Button(onClick = { if (name.isNotBlank()) onSave(name, time, place) }) { Text("添加考试") }
}

@Composable
private fun WorkForm(onSave: (String, String, String) -> Unit) {
    var course by remember { mutableStateOf("") }
    var title by remember { mutableStateOf("") }
    var due by remember { mutableStateOf("2026-11-20T23:59") }
    Field("课程", course) { course = it }
    Field("标题", title) { title = it }
    Field("截止", due) { due = it }
    Button(onClick = { if (title.isNotBlank()) onSave(course, title, due) }) { Text("添加作业") }
}

@Composable
private fun SettingsHome(model: ClassdayModel) {
    val theme = model.theme
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp)) {
        Text("我的", style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Black)
        Text(theme.englishName + " · " + theme.tagline, color = theme.secondary())
        Text("外观", fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 12.dp))
        Row(Modifier.horizontalScroll(rememberScrollState())) {
            ClassdayThemes.all.forEach { item ->
                FilterChip(
                    selected = theme.id == item.id,
                    onClick = { model.setTheme(item.id) },
                    label = { Text(item.name) },
                    modifier = Modifier.padding(end = 6.dp),
                )
            }
        }
        Button(onClick = { model.cycleTheme() }, modifier = Modifier.padding(top = 8.dp).semantics { contentDescription = "换一套" }) { Text("换一套") }
        Row(Modifier.padding(top = 8.dp)) {
            PerformanceTier.entries.forEach { tier ->
                FilterChip(selected = model.document.appearance.performance == tier, onClick = { model.setTier(tier) }, label = { Text(tier.title) }, modifier = Modifier.padding(end = 6.dp))
            }
        }
        Text(model.tier.detail, color = theme.secondary(), fontSize = 12.sp)
        SettingsCard("课表") {
            SettingsRow("上课时间") { model.open(Screen.Periods) }
            SettingsRow("学期") { model.open(Screen.SemesterEdit) }
            SettingsRow("假期与不上课时段") { model.open(Screen.Holidays) }
        }
        SettingsCard("通用") {
            SettingsRow("提醒") { model.ensureReminderDraft(); model.open(Screen.Reminders) }
            SettingsRow("数据") { model.open(Screen.DataPage) }
            SettingsRow("关于") { model.open(Screen.About) }
        }
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
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("第 ${period.index} 节", modifier = Modifier.width(64.dp))
                OutlinedTextField(period.start, { value -> periods = periods.mapIndexed { i, item -> if (i == index) item.copy(start = value) else item } }, modifier = Modifier.weight(1f), label = { Text("开始") })
                Spacer(Modifier.width(8.dp))
                OutlinedTextField(period.end, { value -> periods = periods.mapIndexed { i, item -> if (i == index) item.copy(end = value) else item } }, modifier = Modifier.weight(1f), label = { Text("结束") })
            }
        }
        Button(onClick = { model.saveSemester(model.document.semester.copy(periods = periods)) }, modifier = Modifier.padding(top = 12.dp)) { Text("保存") }
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
        Text("停课", fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 16.dp))
        model.document.semester.cancellations.forEach { entry ->
            Row {
                Text("${entry.date} ${entry.courseName.ifEmpty { "全天" }} ${entry.scope} ${entry.reason}", modifier = Modifier.weight(1f))
                TextButton(onClick = { model.saveSemester(model.document.semester.copy(cancellations = model.document.semester.cancellations.filter { it.id != entry.id })) }) { Text("恢复") }
            }
        }
    }
}

@Composable
private fun ReminderPage(model: ClassdayModel) {
    model.ensureReminderDraft()
    var minutes by remember { mutableStateOf((model.reminderDraft ?: model.document.semester.defaultReminderMinutes).toString()) }
    val context = LocalContext.current
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { }
    Column(Modifier.fillMaxSize().padding(16.dp)) {
        PageTitle("提醒", model::back)
        Field("默认提前分钟", minutes) { minutes = it; model.reminderDraft = it.toIntOrNull() }
        Text("离开这一页也会留着还没保存的数字。", color = model.theme.secondary(), fontSize = 12.sp)
        Button(onClick = {
            if (android.os.Build.VERSION.SDK_INT >= 33) permission.launch(Manifest.permission.POST_NOTIFICATIONS)
            model.saveReminderDraft()
        }, modifier = Modifier.padding(top = 12.dp)) { Text("保存") }
        TextButton(onClick = {
            context.startActivity(Intent(android.provider.Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
                data = Uri.parse("package:${context.packageName}")
            })
        }) { Text("允许精确定时，锁屏倒计时才准") }
    }
}

@Composable
private fun DataPage(model: ClassdayModel) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var share by remember { mutableStateOf("") }
    var icsUrl by remember { mutableStateOf(model.document.subscribedICSURL) }
    var fenixId by remember { mutableStateOf(FenixConfig.prefs(context).getString("clientId", "").orEmpty()) }
    var fenixSecret by remember { mutableStateOf(FenixConfig.prefs(context).getString("secret", "").orEmpty()) }
    var libraryName by remember { mutableStateOf("") }
    val export = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/json")) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        context.contentResolver.openOutputStream(uri)?.use { it.write(model.exportJson().toByteArray()) }
        model.banner = "已导出 JSON"
    }
    val importJson = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        val text = context.contentResolver.openInputStream(uri)?.bufferedReader()?.readText().orEmpty()
        if (text.contains("BEGIN:VCALENDAR")) {
            val parsed = ICSImporter.parse(text, model.calendar, model.document.semester.totalWeeks)
            model.importCalendar(parsed.courses, parsed.exams, parsed.homework)
        } else model.importDocument(text, replace = true)
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
        Button(onClick = { export.launch("classday-${model.document.semester.shortName}.json") }) { Text("导出 JSON") }
        Button(onClick = { importJson.launch(arrayOf("application/json", "text/*", "application/octet-stream")) }) { Text("导入 JSON 或 .ics") }
        Button(onClick = { importCsv.launch(arrayOf("text/*", "application/csv", "application/vnd.ms-excel", "application/octet-stream")) }) { Text("导入 Excel 导出的 CSV") }
        Text("在 Excel 中另存为 CSV UTF-8（不是 .xlsx）。表头可用：课程名称、星期、节次、教室、教师、周次；也支持开始时间和结束时间。预览确认后追加，不替换现有课程。", color = model.theme.secondary(), fontSize = 12.sp)
        OutlinedTextField(icsUrl, { icsUrl = it }, label = { Text("iCal 订阅地址") }, modifier = Modifier.fillMaxWidth())
        Button(onClick = {
            scope.launch {
                val text = withContext(Dispatchers.IO) {
                    try { URL(icsUrl).readText() } catch (_: Exception) { null }
                }
                if (text == null) model.banner = "地址无效，粘贴完整的 iCal 订阅地址再试"
                else {
                    val parsed = ICSImporter.parse(text, model.calendar, model.document.semester.totalWeeks)
                    model.importCalendar(parsed.courses, parsed.exams, parsed.homework, icsUrl)
                }
            }
        }) { Text("订阅并导入") }
        Button(onClick = { photo.launch(androidx.activity.result.PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }) { Text("拍照 / 相册 OCR 导入") }
        OutlinedTextField(fenixId, { fenixId = it }, label = { Text("Fénix client id") }, modifier = Modifier.fillMaxWidth())
        OutlinedTextField(fenixSecret, { fenixSecret = it }, label = { Text("Fénix client secret") }, modifier = Modifier.fillMaxWidth())
        Button(onClick = {
            FenixConfig.prefs(context).edit().putString("clientId", fenixId).putString("secret", fenixSecret).apply()
            if (!FenixAuth.begin(context, fenixId)) model.banner = "先填写 Fénix 的 client id 和 secret"
        }) { Text("用 Fénix 登录并导入") }
        Text("redirect URI 填 classday://fenix。", color = model.theme.secondary(), fontSize = 12.sp)
        val link = ShareCodec.url(model.document)
        Text("分享链接", fontWeight = FontWeight.Bold)
        Text(link.take(180) + if (link.length > 180) "…" else "", fontSize = 11.sp)
        QrImage(link)
        Button(onClick = {
            context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).apply {
                type = "text/plain"
                putExtra(Intent.EXTRA_TEXT, link)
            }, "分享课表"))
        }) { Text("分享链接") }
        OutlinedTextField(share, { share = it }, label = { Text("粘贴分享链接") }, modifier = Modifier.fillMaxWidth())
        Button(onClick = { model.importShare(share) }) { Text("导入分享") }
        Button(onClick = {
            calendarPermission.launch(arrayOf(Manifest.permission.READ_CALENDAR, Manifest.permission.WRITE_CALENDAR))
        }) { Text("同步到系统日历") }
        if (model.duplicates().isNotEmpty()) {
            Button(onClick = { model.open(Screen.Merge) }) { Text("合并同名课程") }
        }
        OutlinedTextField(libraryName, { libraryName = it }, label = { Text("存入课表库的名字") }, modifier = Modifier.fillMaxWidth())
        Button(onClick = { if (libraryName.isNotBlank()) model.storeLibrary(libraryName) }) { Text("保存当前课表") }
        model.document.library.forEach { stored ->
            TextButton(onClick = { model.switchLibrary(stored.id) }) { Text("切换到 ${stored.name}") }
        }
        TextButton(onClick = { model.resetDemo() }) { Text("恢复演示数据") }
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
        Text(model.importNote, color = model.theme.secondary())
        model.importDrafts.forEach { draft ->
            Card(Modifier.fillMaxWidth().padding(vertical = 4.dp)) {
                Column(Modifier.padding(12.dp)) {
                    Text(draft.name, fontWeight = FontWeight.Bold)
                    Text(draft.teacher + " " + draft.location, fontSize = 12.sp)
                    Text("周次：${draft.weeks.joinToString("、")}", fontSize = 12.sp)
                    draft.meetings.forEach { meeting ->
                        Text("${ScheduleCopy.weekdayName(meeting.weekday)} 第 ${meeting.startPeriod ?: "?"} 节 ${meeting.parity.title}", fontSize = 12.sp)
                    }
                }
            }
        }
        Button(onClick = { model.confirmDrafts() }) { Text("写入课表") }
    }
}

@Composable
private fun MergePage(model: ClassdayModel) {
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp)) {
        PageTitle("合并同名课程", model::back)
        Text("合并前会先把当前课表存进课表库。周次和上课时间取并集。", color = model.theme.secondary())
        model.duplicates().forEach { group ->
            var chosen by remember(group.normalizedName) { mutableStateOf(group.courses.firstOrNull { it.grade != null }?.id) }
            Card(Modifier.fillMaxWidth().padding(vertical = 6.dp)) {
                Column(Modifier.padding(12.dp)) {
                    Text(group.courses.first().name, fontWeight = FontWeight.Bold)
                    if (gradeConflict(group)) {
                        Text("成绩不一样，选一个保留")
                        group.courses.filter { it.grade != null }.forEach { course ->
                            FilterChip(selected = chosen == course.id, onClick = { chosen = course.id }, label = { Text("${course.grade}") }, modifier = Modifier.padding(end = 6.dp))
                        }
                    }
                    Button(onClick = { model.merge(group, chosen) }) { Text("合并") }
                }
            }
        }
    }
}

@Composable
private fun AboutPage(model: ClassdayModel) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var status by remember { mutableStateOf("版本 ${com.classday.app.BuildConfig.VERSION_NAME}") }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp)) {
        PageTitle("关于", model::back)
        Text("课曜 / Heptara", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Black)
        Text(status)
        Text("和 iOS 版共用同一份课表 JSON、ICS 和 classday:// 分享。", modifier = Modifier.padding(top = 8.dp))
        Text("常驻通知在课程结束后会写成「已结束，打开课曜查看下一节」，倒计时不再往上数。", modifier = Modifier.padding(top = 8.dp), color = model.theme.secondary())
        Button(onClick = {
            scope.launch {
                status = "正在检查更新…"
                status = com.classday.app.platform.UpdateClient.check(context)
            }
        }, modifier = Modifier.padding(top = 12.dp)) { Text("检查更新") }
        Text("高性能开着色器和粒子，平衡保留动效，省电关掉陀螺仪、着色器和粒子。系统省电或关闭动画时会自动降到省电。", modifier = Modifier.padding(top = 12.dp), fontSize = 13.sp)
    }
}
