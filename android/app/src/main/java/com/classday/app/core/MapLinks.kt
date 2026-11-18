package com.classday.app.core

import java.net.URLEncoder

object MapLinks {
    fun validCoordinates(latitude: Double?, longitude: Double?) = latitude != null && longitude != null &&
        latitude.isFinite() && longitude.isFinite() && latitude in -90.0..90.0 && longitude in -180.0..180.0
    /**
     * 地图实际使用的搜索词。
     * 1) 已绑定过搜索词的教室（RoomPin.query 与名字不同）优先用它；
     * 2) 否则用教室里填的名字；
     * 3) 都没有时退回课程上的地点。
     */
    fun query(location: String, pin: RoomPin?): String {
        val pinned = pin?.query?.trim().orEmpty()
        if (pinned.isNotEmpty() && pinned != pin?.name?.trim().orEmpty()) return pinned
        // 优先级保持旧的语义：课程地点 → 面板里填的教室名
        return listOf(location.trim(), pin?.name?.trim().orEmpty()).firstOrNull { it.isNotEmpty() }.orEmpty()
    }

    /** 这间教室是否已经绑定过精确搜索词（绑定后导航才能搜准）。 */
    fun hasPreciseQuery(location: String, pin: RoomPin?): Boolean {
        val pinned = pin?.query?.trim().orEmpty()
        return pinned.isNotEmpty() && pinned != pin?.name?.trim().orEmpty()
    }
    private fun encode(text: String) = URLEncoder.encode(text, "UTF-8").replace("+", "%20")
    fun search(name: String, latitude: Double?, longitude: Double?): String? {
        val valid = validCoordinates(latitude, longitude)
        if (!valid && name.isBlank()) return null
        return if (valid) "geo:$latitude,$longitude?q=$latitude,$longitude(${encode(name.trim())})"
            else "geo:0,0?q=${encode(name.trim())}"
    }
    fun directions(name: String, latitude: Double?, longitude: Double?): String? {
        if (!validCoordinates(latitude, longitude)) return null
        return "https://www.google.com/maps/dir/?api=1&destination=${encode("$latitude,$longitude")}&travelmode=walking"
    }
    fun amap(name: String, latitude: Double?, longitude: Double?): String? {
        if (!validCoordinates(latitude, longitude)) return search(name, latitude, longitude)
        return "amapuri://route/plan/?sourceApplication=Classday&dlat=$latitude&dlon=$longitude&dname=${encode(name.trim())}&dev=1&t=2&m=0"
    }
    fun baidu(name: String, latitude: Double?, longitude: Double?): String? {
        if (!validCoordinates(latitude, longitude)) return search(name, latitude, longitude)
        return "baidumap://map/direction?origin=${encode("我的位置")}&destination=${encode("latlng:$latitude,$longitude|name:${name.trim()}")}&mode=walking&coord_type=wgs84&src=andr.com.classday.app"
    }
}
