package com.classday.app.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Button
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.classday.app.core.GradeComponent
import com.classday.app.core.GradeScheme
import com.classday.app.core.GradeTerm
import java.util.UUID

/**
 * 记分规则编辑器：按老师的评分说明一步步填。
 * ① 满分与算法 ② 评分项（占比 + 得分 + 最低分）③ 取高方案（可选）④ 结果
 */
@Composable
fun GradeSchemeEditor(
    initial: GradeScheme,
    onSave: (GradeScheme) -> Unit,
) {
    var scheme by remember(initial) { mutableStateOf(if (initial.components.isEmpty()) defaultScheme(initial.scale) else initial) }
    var newComponentName by remember { mutableStateOf("") }

    fun updateComponent(id: String, transform: (GradeComponent) -> GradeComponent) {
        scheme = scheme.copy(components = scheme.components.map { if (it.id == id) transform(it) else it })
    }

    fun updateScore(id: String, raw: String) {
        val value = raw.toDoubleOrNull()
        scheme = scheme.copy(scores = if (value == null) scheme.scores - id else scheme.scores + (id to value))
    }

    /** 占比直接改第一条（默认）方案里的权重。 */
    fun updatePrimaryWeight(id: String, percent: String) {
        val weight = (percent.toDoubleOrNull() ?: 0.0) / 100.0
        val branches = scheme.branches.toMutableList()
        if (branches.isEmpty()) branches.add(emptyList())
        val first = branches[0].toMutableList()
        val index = first.indexOfFirst { it.componentID == id }
        if (index >= 0) first[index] = first[index].copy(weight = weight) else first.add(GradeTerm(id, weight))
        branches[0] = first
        scheme = scheme.copy(branches = branches)
    }

    fun primaryWeight(id: String): String {
        val w = scheme.branches.firstOrNull()?.firstOrNull { it.componentID == id }?.weight ?: 0.0
        val p = w * 100.0
        return if (p == 0.0) "" else if (p % 1.0 == 0.0) p.toInt().toString() else "%.1f".format(p)
    }

    fun updateMinimum(id: String, raw: String) {
        val value = raw.toDoubleOrNull()
        scheme = scheme.copy(minimums = if (value == null) scheme.minimums - id else scheme.minimums + (id to value))
    }

    fun addComponent() {
        val name = newComponentName.ifBlank { "评分项${scheme.components.size + 1}" }
        val component = GradeComponent(UUID.randomUUID().toString(), name)
        val branches = scheme.branches.toMutableList()
        if (branches.isEmpty()) branches.add(emptyList())
        branches[0] = branches[0] + GradeTerm(component.id, 0.0)
        scheme = scheme.copy(components = scheme.components + component, branches = branches)
        newComponentName = ""
    }

    fun removeComponent(id: String) {
        scheme = scheme.copy(
            components = scheme.components.filter { it.id != id },
            scores = scheme.scores - id,
            minimums = scheme.minimums - id,
            branches = scheme.branches.map { branch -> branch.filter { it.componentID != id } },
        )
    }

    fun addBranch() {
        scheme = scheme.copy(branches = scheme.branches + listOf(scheme.branches.firstOrNull() ?: emptyList()))
    }

    fun branchText(branch: List<GradeTerm>): String {
        val parts = branch.filter { it.weight > 0.0 }
            .sortedByDescending { it.weight }
            .map { term ->
                val name = scheme.components.firstOrNull { it.id == term.componentID }?.name ?: "?"
                "${kotlin.math.round(term.weight * 100).toInt()}% $name"
            }
        return if (parts.isEmpty()) "还没填占比" else parts.joinToString(" + ")
    }

    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text("① 满分与算法", fontWeight = FontWeight.Bold)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            FilterChip(selected = scheme.scale == 20.0, onClick = { scheme = scheme.copy(scale = 20.0) }, label = { Text("20 分制") })
            FilterChip(selected = scheme.scale == 100.0, onClick = { scheme = scheme.copy(scale = 100.0) }, label = { Text("100 分制") })
        }
        Text(
            "当前算法：" + (scheme.branches.firstOrNull()?.let { branchText(it) } ?: "还没设算法"),
            fontSize = 12.sp,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text(
            "照着老师的评分说明填：填评分项的名字、占比和得分，总成绩自动算。",
            fontSize = 12.sp,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        Text("② 评分项（占比 + 得分）", fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 6.dp))
        scheme.components.forEach { component ->
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    OutlinedTextField(
                        value = component.name,
                        onValueChange = { name -> updateComponent(component.id) { it.copy(name = name) } },
                        label = { Text("评分项") },
                        singleLine = true,
                        modifier = Modifier.weight(1f),
                    )
                    OutlinedTextField(
                        value = scheme.scores[component.id]?.let { numText(it) } ?: "",
                        onValueChange = { updateScore(component.id, it) },
                        label = { Text("得分") },
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                        modifier = Modifier.width(96.dp),
                    )
                    TextButton(onClick = { removeComponent(component.id) }) { Text("删", color = MaterialTheme.colorScheme.error) }
                }
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    OutlinedTextField(
                        value = primaryWeight(component.id),
                        onValueChange = { updatePrimaryWeight(component.id, it) },
                        label = { Text("占比 %") },
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                        modifier = Modifier.width(110.dp),
                    )
                    OutlinedTextField(
                        value = scheme.minimums[component.id]?.let { numText(it) } ?: "",
                        onValueChange = { updateMinimum(component.id, it) },
                        label = { Text("最低分") },
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                        modifier = Modifier.width(110.dp),
                    )
                    Text("满分 ${numText(scheme.scale)}", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            OutlinedTextField(
                value = newComponentName,
                onValueChange = { newComponentName = it },
                label = { Text("新评分项名") },
                singleLine = true,
                modifier = Modifier.weight(1f),
            )
            TextButton(onClick = { addComponent() }) { Text("添加评分项") }
        }
        Text(
            "占比按老师的写法填：25 就是 25%。最低分只在规则里写了才填（例如期末至少 8 分）。",
            fontSize = 12.sp,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        Text("③ 取高方案（可选）", fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 6.dp))
        scheme.branches.forEachIndexed { index, branch ->
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("方案 ${index + 1}：${branchText(branch)}", fontSize = 12.sp, modifier = Modifier.weight(1f))
                val value = scheme.value(branch)
                if (value != null) Text("${numText(value)} 分", fontSize = 12.sp, fontWeight = FontWeight.Bold)
            }
        }
        TextButton(onClick = { addBranch() }) { Text("再加一条方案（补考 / 期末替代期中）") }
        Text(
            "只有老师允许「几种算法取最高」时才需要加；多条方案时总成绩取最高的一条。新方案默认照抄第一条，只改要变的那几项。",
            fontSize = 12.sp,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        Text("④ 结果", fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 6.dp))
        val final = scheme.finalGrade
        val normalized = scheme.normalizedFinal
        if (final != null && normalized != null) {
            Text("总成绩 ${numText(final)} / ${numText(scheme.scale)}", fontWeight = FontWeight.Bold)
            Text("折合百分制 ${numText(normalized)} · 绩点 ${"%.1f".format(gradePointOf(normalized))}", fontSize = 13.sp)
        } else {
            Text("把任意一条方案里的评分项都填上分，这里就会算出总成绩。", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        scheme.minimumWarnings.forEach { warning ->
            Text("⚠ " + warning, fontSize = 12.sp, color = MaterialTheme.colorScheme.error)
        }

        Button(onClick = { onSave(scheme) }, modifier = Modifier.fillMaxWidth().padding(top = 8.dp)) {
            Text("保存记分规则")
        }
    }
}

/** 默认模板：小组项目 25% / 期中测验 25% / 期末考试 50%。 */
fun defaultScheme(scale: Double = 100.0): GradeScheme {
    val project = GradeComponent(UUID.randomUUID().toString(), "小组项目")
    val midterm = GradeComponent(UUID.randomUUID().toString(), "期中测验")
    val exam = GradeComponent(UUID.randomUUID().toString(), "期末考试")
    return GradeScheme(
        scale = scale,
        components = listOf(project, midterm, exam),
        branches = listOf(
            listOf(
                GradeTerm(project.id, 0.25),
                GradeTerm(midterm.id, 0.25),
                GradeTerm(exam.id, 0.50),
            )
        ),
    )
}

/** 百分制转 4.0 制绩点（与 iOS AppModel.gradePoint 一致的分段）。 */
private fun gradePointOf(percent: Double): Double = when {
    percent >= 90 -> 4.0
    percent >= 85 -> 3.7
    percent >= 82 -> 3.3
    percent >= 78 -> 3.0
    percent >= 75 -> 2.7
    percent >= 72 -> 2.3
    percent >= 68 -> 2.0
    percent >= 64 -> 1.5
    percent >= 60 -> 1.0
    else -> 0.0
}

private fun numText(value: Double): String =
    if (value % 1.0 == 0.0) value.toInt().toString() else "%.2f".format(value).trimEnd('0').trimEnd('.')