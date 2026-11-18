package com.classday.app
import com.classday.app.core.*
import org.junit.Assert.*
import org.junit.Test
class UpdateIntegrityTest {
    private val release = ReleaseEntry("2.9.5", "Classday-android-v2.9.5.apk", 123, "a".repeat(64), "https://example.invalid/app.apk", "2026-11-15")
    @Test fun exactSizeAndHashAreBothRequired() {
        assertTrue(UpdateIntegrity.matches(release, 123, "A".repeat(64)))
        assertFalse(UpdateIntegrity.matches(release, 122, release.sha256))
        assertFalse(UpdateIntegrity.matches(release, 124, release.sha256))
        assertFalse(UpdateIntegrity.matches(release, 123, "b".repeat(64)))
    }
    @Test fun rejectsUnsafeArtifactMetadata() {
        assertFalse(UpdateIntegrity.safe(release.copy(file = "../app.apk")))
        assertFalse(UpdateIntegrity.safe(release.copy(downloadUrl = "file:///tmp/app.apk")))
        assertFalse(UpdateIntegrity.safe(release.copy(downloadUrl = "https://token@example.invalid/app.apk")))
        assertFalse(UpdateIntegrity.safe(release.copy(sha256 = "")))
        assertFalse(UpdateIntegrity.safe(release.copy(size = 0)))
    }
    @Test fun manifestSourceStaysOnThePublicArchiveNotTheRetiredHost() {
        assertEquals("https://gitlab.com/yuanyeye0210/classday-releases/-/raw/main/latest.json", UpdateManifest.manifestUrl)
        assertFalse(UpdateManifest.manifestUrl.contains("github", ignoreCase = true))
        val uri = java.net.URI(UpdateManifest.manifestUrl)
        assertEquals("https", uri.scheme)
        assertNull(uri.userInfo)
    }
    @Test fun pendingPublicationIsNotClaimedUpToDate() {
        assertTrue(UpdateIntegrity.failure(404).contains("尚未发布"))
        assertTrue(UpdateIntegrity.failure(403).contains("公开读取"))
        assertTrue(UpdateIntegrity.failure(null).contains("网络"))
        assertFalse(UpdateIntegrity.failure(404).contains("最新版"))
    }
}
