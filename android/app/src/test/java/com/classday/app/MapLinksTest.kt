package com.classday.app

import com.classday.app.core.*
import java.net.URI
import java.net.URLDecoder
import org.junit.Assert.*
import org.junit.Test

class MapLinksTest {
    private fun params(url: String) = URI(url).rawQuery.split("&").associate {
        val pair = it.split("=", limit = 2)
        pair[0] to URLDecoder.decode(pair.getOrElse(1) { "" }, "UTF-8")
    }
    @Test fun coordinatesMustBeCompleteFiniteAndInRange() {
        assertFalse(MapLinks.validCoordinates(null, 1.0))
        assertFalse(MapLinks.validCoordinates(1.0, null))
        assertFalse(MapLinks.validCoordinates(Double.NaN, 0.0))
        assertFalse(MapLinks.validCoordinates(0.0, Double.POSITIVE_INFINITY))
        assertFalse(MapLinks.validCoordinates(91.0, 0.0))
        assertFalse(MapLinks.validCoordinates(0.0, -181.0))
        assertTrue(MapLinks.validCoordinates(0.0, 0.0))
        assertTrue(MapLinks.validCoordinates(-90.0, 180.0))
    }
    @Test fun emptyTargetDoesNotProduceCoordinatesOrRoute() {
        assertNull(MapLinks.search(" ", null, null))
        assertNull(MapLinks.amap("", null, null))
        assertNull(MapLinks.baidu("", Double.NaN, 1.0))
        assertNull(MapLinks.directions("Room", 91.0, 0.0))
    }
    @Test fun searchKeepsSpecialCharactersAndDoesNotInjectAnotherParameter() {
        val query = "校区 A&B #2 / 301"
        val url = MapLinks.search(query, null, null)!!
        val decoded = URLDecoder.decode(url.substringAfter("?q="), "UTF-8")
        assertEquals(query, decoded)
        assertFalse(url.contains("&B"))
        assertFalse(url.contains("#"))
        assertEquals(url, MapLinks.amap(query, null, null))
    }
    @Test fun coordinateSearchUsesCoordinatesAndKeepsLabelEncoded() {
        val query = "主楼 A&B #2"
        val url = MapLinks.search(query, 51.5, -0.1)!!
        assertEquals("geo", URI(url).scheme)
        assertTrue(url.startsWith("geo:51.5,-0.1?q=51.5,-0.1("))
        assertFalse(url.contains(" "))
        assertFalse(url.contains("&"))
        assertEquals(query, URLDecoder.decode(url.substringAfter("(").removeSuffix(")"), "UTF-8"))
    }
    @Test fun validCoordinatesCanRouteWithoutAName() {
        assertNotNull(MapLinks.search("", 51.5, -0.1))
        val route = params(MapLinks.directions("", 51.5, -0.1)!!)
        assertEquals("51.5,-0.1", route["destination"])
        assertEquals("walking", route["travelmode"])
    }
    @Test fun vendorRoutesUseWalkingAndExplicitOriginalCoordinateType() {
        val query = "A&B #2"
        val a = MapLinks.amap(query, 51.5, -0.1)!!
        assertEquals("amapuri", URI(a).scheme)
        assertEquals("2", params(a)["t"])
        assertEquals("1", params(a)["dev"])
        assertEquals(query, params(a)["dname"])
        val b = MapLinks.baidu(query, 51.5, -0.1)!!
        assertEquals("baidumap", URI(b).scheme)
        assertEquals("walking", params(b)["mode"])
        assertEquals("wgs84", params(b)["coord_type"])
        assertEquals("latlng:51.5,-0.1|name:A&B #2", params(b)["destination"])
    }
    @Test fun explicitSearchQueryWinsThenLocationThenPinName() {
        assertEquals("校区", MapLinks.query("教室", RoomPin("p", "楼", query = " 校区 ")))
        assertEquals("教室", MapLinks.query(" 教室 ", RoomPin("p", "楼", query = " ")))
        assertEquals("楼", MapLinks.query("", RoomPin("p", " 楼 ", query = "")))
    }
}
