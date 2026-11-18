package com.classday.app

import com.classday.app.core.CourseReminder
import org.junit.Assert.assertEquals
import org.junit.Test

class CourseReminderTest {
    @Test
    fun nullLeadInheritsSemesterDefault() {
        assertEquals(10, CourseReminder.effectiveLead(null, 10))
        assertEquals(15, CourseReminder.nextLead(null, 10))
    }

    @Test
    fun explicitZeroMeansOffInsteadOfInheritingDefault() {
        assertEquals(0, CourseReminder.effectiveLead(0, 10))
        assertEquals(5, CourseReminder.nextLead(0, 10))
    }

    @Test
    fun zeroSemesterDefaultAlsoCyclesUpFromOff() {
        assertEquals(5, CourseReminder.nextLead(null, 0))
    }

    @Test
    fun positiveLeadMovesToNextStep() {
        assertEquals(15, CourseReminder.nextLead(10, 0))
        assertEquals(30, CourseReminder.nextLead(20, 0))
    }

    @Test
    fun topStepWrapsBackToOff() {
        assertEquals(0, CourseReminder.nextLead(30, 0))
    }

    @Test
    fun nonStepLeadSnapsToNextAvailableStep() {
        assertEquals(10, CourseReminder.nextLead(7, 0))
        assertEquals(5, CourseReminder.nextLead(1, 0))
    }

    @Test
    fun negativeLeadIsTreatedAsOff() {
        assertEquals(0, CourseReminder.effectiveLead(-5, 10))
        assertEquals(5, CourseReminder.nextLead(-5, 10))
    }
}
