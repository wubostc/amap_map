package com.amap.flutter.map2;

import android.Manifest;
import android.content.Context;
import android.content.pm.PackageManager;
import android.location.LocationManager;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;

import androidx.annotation.NonNull;

import com.amap.api.location.AMapLocation;
import com.amap.api.location.AMapLocationClient;
import com.amap.api.location.AMapLocationClientOption;
import com.amap.api.location.AMapLocationListener;
import com.amap.api.maps.AMapUtils;
import com.amap.api.maps.MapsInitializer;
import com.amap.api.maps.model.LatLng;
import com.amap.api.services.core.AMapException;
import com.amap.api.services.core.LatLonPoint;
import com.amap.api.services.core.PoiItem;
import com.amap.api.services.core.PoiItemV2;
import com.amap.api.services.core.ServiceSettings;
import com.amap.api.services.geocoder.GeocodeAddress;
import com.amap.api.services.geocoder.GeocodeQuery;
import com.amap.api.services.geocoder.GeocodeResult;
import com.amap.api.services.geocoder.GeocodeSearch;
import com.amap.api.services.geocoder.RegeocodeAddress;
import com.amap.api.services.geocoder.RegeocodeQuery;
import com.amap.api.services.geocoder.RegeocodeResult;
import com.amap.api.services.geocoder.StreetNumber;
import com.amap.api.services.poisearch.Business;
import com.amap.api.services.poisearch.IndoorDataV2;
import com.amap.api.services.poisearch.Photo;
import com.amap.api.services.poisearch.PoiNavi;
import com.amap.api.services.poisearch.PoiResultV2;
import com.amap.api.services.poisearch.PoiSearchV2;
import com.amap.api.services.poisearch.SubPoiItemV2;
import com.amap.flutter.map2.utils.ConvertUtil;
import com.amap.flutter.map2.utils.LogUtil;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/**
 * 独立定位和地理编码的应用级通道控制器，不依赖地图 PlatformView。
 */
final class AMapServicesController implements MethodChannel.MethodCallHandler,
        EventChannel.StreamHandler {
    private final Context context;
    private final Handler handler = new Handler(Looper.getMainLooper());
    private volatile EventChannel.EventSink eventSink;
    private volatile boolean disposed;
    private final Object singleOperationLock = new Object();
    private final Object searchOperationLock = new Object();
    // 单次和连续定位使用不同实例，避免单次请求中断正在运行的连续定位。
    private AMapLocationClient continuousClient;
    private AMapLocationClient singleClient;
    private MethodChannel.Result singleResult;
    private Runnable singleTimeout;
    // SDK 的搜索回调是异步的，请求完成前需要强引用 GeocodeSearch。
    private final Map<GeocodeSearch, MethodChannel.Result> geocodeSearches = new LinkedHashMap<>();
    // PoiSearchV2 没有公开单请求取消方法，保留实例以便在生命周期结束
    // 时解绑监听并完成 Flutter Result。
    private final Map<PoiSearchV2, MethodChannel.Result> poiSearches = new LinkedHashMap<>();

    AMapServicesController(Context context) {
        Context applicationContext = context.getApplicationContext();
        this.context = applicationContext == null ? context : applicationContext;
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        if (disposed) {
            result.error("services_disposed", "高德服务控制器已销毁。", null);
            return;
        }
        switch (call.method) {
            case "services#initialize":
                initialize(call.arguments, result);
                break;
            case "services#updatePrivacy":
                updatePrivacy(arguments(call), result);
                break;
            case "location#getCurrent":
                getCurrentLocation(arguments(call), result);
                break;
            case "location#start":
                startLocation(arguments(call), result);
                break;
            case "location#stop":
                stopContinuousLocation();
                result.success(null);
                break;
            case "geocoding#geocode":
                geocode(arguments(call), result);
                break;
            case "geocoding#reverseGeocode":
                reverseGeocode(arguments(call), result);
                break;
            case "poiSearch#search":
                poiSearch(arguments(call), result);
                break;
            default:
                result.notImplemented();
                break;
        }
    }

    private void initialize(Object arguments, MethodChannel.Result result) {
        Map<?, ?> values = arguments instanceof Map ? (Map<?, ?>) arguments : new HashMap<>();
        Map<?, ?> privacy = values.get("privacyStatement") instanceof Map
                ? (Map<?, ?>) values.get("privacyStatement") : new HashMap<>();
        boolean contains = Boolean.TRUE.equals(privacy.get("hasContains"));
        boolean shown = Boolean.TRUE.equals(privacy.get("hasShow"));
        boolean agreed = Boolean.TRUE.equals(privacy.get("hasAgree"));
        if (!contains || !shown || !agreed) {
            result.error("privacy_not_agreed", "使用高德服务前必须完成隐私合规配置。", null);
            return;
        }

        // 高德要求在创建任一 SDK 客户端之前分别初始化各模块的隐私状态。
        applyPrivacy(privacy);

        Object apiKeyValue = values.get("apiKey");
        if (apiKeyValue instanceof Map) {
            Object androidKey = ((Map<?, ?>) apiKeyValue).get("androidKey");
            if (androidKey instanceof String && !((String) androidKey).isEmpty()) {
                String key = (String) androidKey;
                MapsInitializer.setApiKey(key);
                AMapLocationClient.setApiKey(key);
                ServiceSettings.getInstance().setApiKey(key);
            }
        }
        result.success(null);
    }

    private void updatePrivacy(Map<?, ?> privacy, MethodChannel.Result result) {
        boolean allowed = isPrivacyAllowed(privacy);
        if (!allowed) {
            cancelActiveOperations();
        }
        applyPrivacy(privacy);
        result.success(null);
    }

    private void applyPrivacy(Map<?, ?> privacy) {
        ConvertUtil.setPrivacyStatement(context, privacy);
    }

    private static boolean isPrivacyAllowed(Map<?, ?> privacy) {
        return Boolean.TRUE.equals(privacy.get("hasContains"))
                && Boolean.TRUE.equals(privacy.get("hasShow"))
                && Boolean.TRUE.equals(privacy.get("hasAgree"));
    }

    private void getCurrentLocation(Map<?, ?> options, MethodChannel.Result result) {
        if (!hasLocationPermission(result)) {
            return;
        }
        synchronized (singleOperationLock) {
            if (disposed) {
                result.error("services_disposed", "高德服务控制器已销毁。", null);
                return;
            }
            if (singleResult != null) {
                result.error("location_busy", "已有单次定位请求正在执行。", null);
                return;
            }
            singleResult = result;
        }
        try {
            final AMapLocationClient client = new AMapLocationClient(context);
            boolean clientStillActive;
            synchronized (singleOperationLock) {
                clientStillActive = !disposed && singleResult != null;
                if (clientStillActive) {
                    singleClient = client;
                }
            }
            if (!clientStillActive) {
                destroyLocationClient(client, "single location");
                return;
            }
            client.setLocationOption(locationOptions(options, true));
            client.setLocationListener(location -> handler.post(() -> {
                if (location != null && location.getErrorCode() == AMapLocation.LOCATION_SUCCESS) {
                    finishSingle(location, null, null);
                } else {
                    String message = location == null ? "定位 SDK 未返回位置。"
                            : location.getErrorInfo() + " (" + location.getErrorCode() + ")";
                    finishSingle(null, "location_failed", message);
                }
            }));
            long timeout = longValue(options.get("timeout"), 10000L);
            Runnable timeoutTask = () -> finishSingle(null, "location_timeout", "定位超时。");
            synchronized (singleOperationLock) {
                clientStillActive = !disposed && singleClient == client && singleResult != null;
                if (clientStillActive) {
                    singleTimeout = timeoutTask;
                }
            }
            if (!clientStillActive) {
                destroyLocationClient(client, "single location");
                return;
            }
            handler.postDelayed(timeoutTask, timeout);
            client.startLocation();
        } catch (Exception exception) {
            finishSingle(null, "location_failed", exception.getMessage());
        }
    }

    private void startLocation(Map<?, ?> options, MethodChannel.Result result) {
        if (!hasLocationPermission(result)) {
            return;
        }
        if (disposed) {
            result.error("services_disposed", "高德服务控制器已销毁。", null);
            return;
        }
        stopContinuousLocation();
        try {
            final AMapLocationClient client = new AMapLocationClient(context);
            boolean clientStillActive;
            synchronized (singleOperationLock) {
                clientStillActive = !disposed;
                if (clientStillActive) {
                    continuousClient = client;
                }
            }
            if (!clientStillActive) {
                destroyLocationClient(client, "continuous location");
                result.error("services_disposed", "高德服务控制器已销毁。", null);
                return;
            }
            client.setLocationOption(locationOptions(options, false));
            client.setLocationListener(new AMapLocationListener() {
                @Override
                public void onLocationChanged(AMapLocation location) {
                    handler.post(() -> emitLocation(location));
                }
            });
            client.startLocation();
            result.success(null);
        } catch (Exception exception) {
            stopContinuousLocation();
            result.error("location_failed", exception.getMessage(), null);
        }
    }

    private void emitLocation(AMapLocation location) {
        EventChannel.EventSink sink = eventSink;
        if (disposed || sink == null) {
            return;
        }
        if (location != null && location.getErrorCode() == AMapLocation.LOCATION_SUCCESS) {
            sink.success(locationToMap(location));
        } else {
            String message = location == null ? "定位 SDK 未返回位置。"
                    : location.getErrorInfo() + " (" + location.getErrorCode() + ")";
            sink.error("location_failed", message, null);
        }
    }

    private AMapLocationClientOption locationOptions(Map<?, ?> values, boolean once) {
        AMapLocationClientOption option = new AMapLocationClientOption();
        String accuracy = String.valueOf(values.get("accuracy"));
        if ("balanced".equals(accuracy)) {
            option.setLocationMode(AMapLocationClientOption.AMapLocationMode.Battery_Saving);
        } else {
            option.setLocationMode(AMapLocationClientOption.AMapLocationMode.Hight_Accuracy);
        }
        // 不请求地址信息，确保定位流程不隐式执行逆地理编码。
        option.setNeedAddress(false);
        // 中国境内将定位结果偏移为可直接用于高德地图的 GCJ-02 坐标。
        option.setOffset(true);
        option.setOnceLocation(once);
        option.setOnceLocationLatest(once);
        option.setHttpTimeOut(longValue(values.get("timeout"), 10000L));
        option.setInterval(Math.max(1000L, longValue(values.get("interval"), 2000L)));
        return option;
    }

    private void geocode(Map<?, ?> values, MethodChannel.Result result) {
        Object addressValue = values.get("address");
        if (!(addressValue instanceof String) || ((String) addressValue).trim().isEmpty()) {
            result.error("geocode_invalid_argument", "地址不能为空。", null);
            return;
        }
        GeocodeSearch search = null;
        try {
            search = new GeocodeSearch(context);
            final GeocodeSearch activeSearch = search;
            synchronized (searchOperationLock) {
                if (disposed) {
                    result.error("services_disposed", "高德服务控制器已销毁。", null);
                    return;
                }
                geocodeSearches.put(search, result);
            }
            activeSearch.setOnGeocodeSearchListener(new GeocodeSearch.OnGeocodeSearchListener() {
                @Override
                public void onRegeocodeSearched(RegeocodeResult ignored, int code) {
                    // 当前搜索实例只处理正向地理编码。
                }

                @Override
                public void onGeocodeSearched(GeocodeResult geocodeResult, int code) {
                    handler.post(() -> {
                        // Claim the request on the main thread.  Disposal also
                        // runs here, so it can win the race and complete the
                        // Result exactly once before this callback is handled.
                        MethodChannel.Result pendingResult = takeGeocodeResult(activeSearch);
                        if (pendingResult == null) {
                            return;
                        }
                        detachGeocodeListener(activeSearch);
                        try {
                            if (disposed) {
                                pendingResult.error("services_disposed", "高德服务控制器已销毁。", null);
                                return;
                            }
                            if (code != AMapException.CODE_AMAP_SUCCESS || geocodeResult == null) {
                                pendingResult.error("geocode_failed", "地理编码失败 (" + code + ")。", code);
                                return;
                            }
                            List<Map<String, Object>> output = new ArrayList<>();
                            List<GeocodeAddress> addresses = geocodeResult.getGeocodeAddressList();
                            if (addresses != null) {
                                for (GeocodeAddress address : addresses) {
                                    if (address != null) {
                                        output.add(geocodeToMap(address));
                                    }
                                }
                            }
                            pendingResult.success(output);
                        } catch (Throwable error) {
                            pendingResult.error("geocode_failed", "地理编码结果处理失败。", error.getMessage());
                        }
                    });
                }
            });
            String city = values.get("city") instanceof String ? (String) values.get("city") : "";
            activeSearch.getFromLocationNameAsyn(new GeocodeQuery(((String) addressValue).trim(), city));
        } catch (AMapException exception) {
            if (search != null) {
                removeGeocodeResultAndDetach(search);
            }
            result.error("geocode_failed", exception.getErrorMessage(), exception.getErrorCode());
        } catch (RuntimeException exception) {
            if (search != null) {
                removeGeocodeResultAndDetach(search);
            }
            result.error("geocode_failed", exception.getMessage(), null);
        }
    }

    private void reverseGeocode(Map<?, ?> values, MethodChannel.Result result) {
        Object locationValue = values.get("location");
        if (!(locationValue instanceof List) || ((List<?>) locationValue).size() < 2
                || !(((List<?>) locationValue).get(0) instanceof Number)
                || !(((List<?>) locationValue).get(1) instanceof Number)) {
            result.error("reverse_geocode_invalid_argument", "坐标格式无效。", null);
            return;
        }
        List<?> location = (List<?>) locationValue;
        double latitude = ((Number) location.get(0)).doubleValue();
        double longitude = ((Number) location.get(1)).doubleValue();
        float radius = values.get("radius") instanceof Number
                ? ((Number) values.get("radius")).floatValue() : 1000F;
        GeocodeSearch search = null;
        try {
            search = new GeocodeSearch(context);
            final GeocodeSearch activeSearch = search;
            synchronized (searchOperationLock) {
                if (disposed) {
                    result.error("services_disposed", "高德服务控制器已销毁。", null);
                    return;
                }
                geocodeSearches.put(search, result);
            }
            activeSearch.setOnGeocodeSearchListener(new GeocodeSearch.OnGeocodeSearchListener() {
                @Override
                public void onRegeocodeSearched(RegeocodeResult regeocodeResult, int code) {
                    handler.post(() -> {
                        MethodChannel.Result pendingResult = takeGeocodeResult(activeSearch);
                        if (pendingResult == null) {
                            return;
                        }
                        detachGeocodeListener(activeSearch);
                        try {
                            if (disposed) {
                                pendingResult.error("services_disposed", "高德服务控制器已销毁。", null);
                                return;
                            }
                            RegeocodeAddress address = regeocodeResult == null
                                    ? null : regeocodeResult.getRegeocodeAddress();
                            if (code != AMapException.CODE_AMAP_SUCCESS || address == null) {
                                pendingResult.error("reverse_geocode_failed",
                                        "逆地理编码失败 (" + code + ")。", code);
                                return;
                            }
                            pendingResult.success(reverseGeocodeToMap(address, latitude, longitude));
                        } catch (Throwable error) {
                            pendingResult.error("reverse_geocode_failed", "逆地理编码结果处理失败。", error.getMessage());
                        }
                    });
                }

                @Override
                public void onGeocodeSearched(GeocodeResult ignored, int code) {
                    // 当前搜索实例只处理逆地理编码。
                }
            });
            RegeocodeQuery query = new RegeocodeQuery(
                    new LatLonPoint(latitude, longitude), radius, GeocodeSearch.AMAP);
            activeSearch.getFromLocationAsyn(query);
        } catch (AMapException exception) {
            if (search != null) {
                removeGeocodeResultAndDetach(search);
            }
            result.error("reverse_geocode_failed",
                    exception.getErrorMessage(), exception.getErrorCode());
        } catch (RuntimeException exception) {
            if (search != null) {
                removeGeocodeResultAndDetach(search);
            }
            result.error("reverse_geocode_failed", exception.getMessage(), null);
        }
    }

    private void poiSearch(Map<?, ?> values, MethodChannel.Result result) {
        if (disposed) {
            result.error("services_disposed", "高德服务控制器已销毁。", null);
            return;
        }
        String mode = stringValue(values.get("mode"), "keyword");
        String keyword = stringValue(values.get("keyword"), "").trim();
        String category = stringOrNull(values.get("types"));
        String city = stringOrNull(values.get("city"));
        if (category == null) {
            category = "";
        }
        if (city == null) {
            city = "";
        }
        int page = intValue(values.get("page"), 1);
        int pageSize = intValue(values.get("pageSize"), 20);
        int showFields = intValue(values.get("showFields"), 0);
        if (page < 1 || page > 100) {
            result.error("poi_search_invalid_argument", "页码必须在 1 到 100 之间。", null);
            return;
        }
        if (pageSize < 1 || pageSize > 25) {
            result.error("poi_search_invalid_argument", "每页数量必须在 1 到 25 之间。", null);
            return;
        }
        if (!"keyword".equals(mode) && !"around".equals(mode)) {
            result.error("poi_search_invalid_argument", "不支持的 POI 查询类型。", null);
            return;
        }
        if (keyword.isEmpty() && category.isEmpty()) {
            result.error("poi_search_invalid_argument", "keyword 和 types 至少提供一个。", null);
            return;
        }
        boolean cityLimit = booleanValue(values.get("cityLimit"), false);
        if ("keyword".equals(mode) && cityLimit && city.isEmpty()) {
            result.error("poi_search_invalid_argument", "cityLimit 为 true 时必须提供 city。", null);
            return;
        }
        final LatLonPoint location = latLonPoint(values.get("location"));
        // Only around searches have a distance center in the public API. A
        // keyword query may also carry a location for sorting, but the native
        // SDK does not define a per-result distance for that mode.
        final LatLonPoint distanceOrigin = "around".equals(mode) ? location : null;
        final int radius = intValue(values.get("radius"), 3000);
        if ("around".equals(mode) && location == null) {
            result.error("poi_search_invalid_argument", "周边查询必须提供中心坐标。", null);
            return;
        }
        if ("around".equals(mode) && (radius < 1 || radius > 50000)) {
            result.error("poi_search_invalid_argument", "查询半径必须在 1 到 50000 米之间。", null);
            return;
        }
        String queryLanguage = stringOrNull(values.get("queryLanguage"));
        if (queryLanguage == null) {
            queryLanguage = PoiSearchV2.CHINESE;
        }
        if (queryLanguage != null
                && !PoiSearchV2.CHINESE.equals(queryLanguage)
                && !PoiSearchV2.ENGLISH.equals(queryLanguage)) {
            result.error("poi_search_invalid_argument", "只支持 zh-CN 或 en。", null);
            return;
        }
        try {
            // The SDK's three-argument constructor requires a non-empty city.
            // Use the two-argument form when the caller intentionally searches
            // without a city restriction.
            PoiSearchV2.Query query = city.isEmpty()
                    ? new PoiSearchV2.Query(keyword, category)
                    : new PoiSearchV2.Query(keyword, category, city);
            query.setPageNum(page);
            query.setPageSize(pageSize);
            // Around requests have no city-limit equivalent on iOS; keep the
            // shared API behavior consistent by applying it to keyword mode only.
            query.setCityLimit("keyword".equals(mode) && cityLimit);
            query.setDistanceSort(booleanValue(values.get("distanceSort"), true));
            query.setBuilding(stringOrNull(values.get("building")));
            query.setSpecial(booleanValue(values.get("special"), true));
            query.setQueryLanguage(queryLanguage);
            String channel = stringOrNull(values.get("channel"));
            if (channel != null) {
                query.setChannel(channel);
            }
            query.setPremium("entirety".equals(values.get("premium"))
                    ? PoiSearchV2.PremiumType.ENTIRETY
                    : PoiSearchV2.PremiumType.DEFAULT);
            query.setShowFields(new PoiSearchV2.ShowFields(
                    androidShowFieldsMask(showFields)));
            query.setCustomParams(stringMap(values.get("customParams")));

            final boolean includeIndoor = showFields < 0 || (showFields & (1 << 3)) != 0;
            if (location != null) {
                query.setLocation(location);
            }

            final PoiSearchV2 search = new PoiSearchV2(context, query);
            if ("around".equals(mode)) {
                search.setBound(new PoiSearchV2.SearchBound(
                        location, radius, query.isDistanceSort()));
            }

            synchronized (searchOperationLock) {
                if (disposed) {
                    result.error("services_disposed", "高德服务控制器已销毁。", null);
                    return;
                }
                poiSearches.put(search, result);
            }
            search.setOnPoiSearchListener(new PoiSearchV2.OnPoiSearchListener() {
                @Override
                public void onPoiSearched(PoiResultV2 poiResult, int code) {
                    handler.post(() -> {
                        MethodChannel.Result pendingResult = takePoiResult(search);
                        if (pendingResult == null) {
                            return;
                        }
                        detachPoiListener(search);
                        try {
                            if (disposed) {
                                pendingResult.error("services_disposed", "高德服务控制器已销毁。", null);
                                return;
                            }
                            if (code != AMapException.CODE_AMAP_SUCCESS || poiResult == null) {
                                pendingResult.error("poi_search_failed",
                                        "POI 搜索失败 (" + code + ")。", code);
                                return;
                            }
                            pendingResult.success(
                                    poiResultToMap(poiResult, includeIndoor, distanceOrigin));
                        } catch (Throwable error) {
                            pendingResult.error("poi_search_failed", "POI 搜索结果处理失败。", error.getMessage());
                        }
                    });
                }

                @Override
                public void onPoiItemSearched(PoiItemV2 ignored, int code) {
                    // 当前通道只执行列表查询。
                }

                @Override
                public void onVisualSearched(
                        com.amap.api.services.poisearch.VisualSearchResult ignored, int code) {
                    // 当前通道只执行列表查询。
                }
            });
            try {
                search.searchPOIAsyn();
            } catch (IllegalArgumentException exception) {
                removePoiResultAndDetach(search);
                result.error("poi_search_invalid_argument", exception.getMessage(), null);
            } catch (RuntimeException exception) {
                removePoiResultAndDetach(search);
                result.error("poi_search_failed", exception.getMessage(), null);
            }
        } catch (AMapException exception) {
            result.error("poi_search_failed", exception.getErrorMessage(), exception.getErrorCode());
        } catch (IllegalArgumentException exception) {
            result.error("poi_search_invalid_argument", exception.getMessage(), null);
        } catch (RuntimeException exception) {
            result.error("poi_search_failed", exception.getMessage(), null);
        }
    }

    private static Map<String, Object> poiResultToMap(
            PoiResultV2 poiResult, boolean includeIndoor, LatLonPoint distanceOrigin) {
        Map<String, Object> map = new HashMap<>();
        PoiSearchV2.Query query = poiResult.getQuery();
        map.put("totalCount", poiResult.getCount());
        map.put("page", query == null ? 1 : query.getPageNum());
        map.put("pageSize", query == null ? 20 : query.getPageSize());
        List<Map<String, Object>> pois = new ArrayList<>();
        List<PoiItemV2> items = poiResult.getPois();
        if (items != null) {
            for (PoiItemV2 item : items) {
                if (item != null && item.getLatLonPoint() != null) {
                    pois.add(poiItemToMap(item, includeIndoor, distanceOrigin));
                }
            }
        }
        map.put("pois", pois);
        return map;
    }

    private static Map<String, Object> poiItemToMap(
            PoiItemV2 item, boolean includeIndoor, LatLonPoint distanceOrigin) {
        Map<String, Object> map = new HashMap<>();
        putIfNotNull(map, "id", item.getPoiId());
        putIfNotNull(map, "name", item.getTitle());
        String snippet = item.getSnippet();
        putIfNotNull(map, "address", snippet);
        putIfNotNull(map, "snippet", snippet);
        putIfNotNull(map, "type", item.getTypeDes());
        putIfNotNull(map, "typeCode", item.getTypeCode());
        putIfNotNull(map, "adCode", item.getAdCode());
        putIfNotNull(map, "city", item.getCityName());
        putIfNotNull(map, "cityCode", item.getCityCode());
        putIfNotNull(map, "province", item.getProvinceName());
        putIfNotNull(map, "provinceCode", item.getProvinceCode());
        putIfNotNull(map, "district", item.getAdName());
        LatLonPoint poiLocation = item.getLatLonPoint();
        putIfNotNull(map, "location", latLonPointToList(poiLocation));
        if (distanceOrigin != null && poiLocation != null) {
            // PoiItemV2 does not expose the search distance. Use the map SDK's
            // own geometry utility so Dart does not reimplement the formula.
            LatLng origin = new LatLng(
                    distanceOrigin.getLatitude(), distanceOrigin.getLongitude());
            LatLng target = new LatLng(
                    poiLocation.getLatitude(), poiLocation.getLongitude());
            map.put("distance", (double) AMapUtils.calculateLineDistance(origin, target));
        }
        Business business = item.getBusiness();
        if (business != null) {
            putIfNotNull(map, "businessArea", business.getBusinessArea());
            putIfNotNull(map, "rating", business.getmRating());
            putIfNotNull(map, "cost", business.getCost());
            putIfNotNull(map, "parkingType", business.getParkingType());
            putIfNotNull(map, "alias", business.getAlias());
            putIfNotNull(map, "tel", business.getTel());
        }

        IndoorDataV2 indoor = item.getIndoorData();
        if (includeIndoor) {
            map.put("hasIndoorMap", indoor != null && indoor.isIndoorMap());
        }

        PoiNavi navi = item.getPoiNavi();
        if (navi != null) {
            putIfNotNull(map, "naviPoiId", navi.getNaviPoiID());
            putIfNotNull(map, "gridCode", navi.getGridCode());
            putIfNotNull(map, "enterLocation", latLonPointToList(navi.getEnter()));
            putIfNotNull(map, "exitLocation", latLonPointToList(navi.getExit()));
        }

        List<Photo> photos = item.getPhotos();
        List<Map<String, Object>> photoMaps = new ArrayList<>();
        if (photos != null) {
            for (Photo photo : photos) {
                if (photo == null) {
                    continue;
                }
                Map<String, Object> photoMap = new HashMap<>();
                putIfNotNull(photoMap, "title", photo.getTitle());
                putIfNotNull(photoMap, "url", photo.getUrl());
                photoMaps.add(photoMap);
            }
        }
        map.put("photos", photoMaps);

        List<SubPoiItemV2> subPois = item.getSubPois();
        List<Map<String, Object>> subPoiMaps = new ArrayList<>();
        if (subPois != null) {
            for (SubPoiItemV2 subPoi : subPois) {
                if (subPoi == null) {
                    continue;
                }
                Map<String, Object> subPoiMap = new HashMap<>();
                putIfNotNull(subPoiMap, "id", subPoi.getPoiId());
                putIfNotNull(subPoiMap, "name", subPoi.getTitle());
                putIfNotNull(subPoiMap, "snippet", subPoi.getSnippet());
                putIfNotNull(subPoiMap, "typeCode", subPoi.getTypeCode());
                putIfNotNull(subPoiMap, "location", latLonPointToList(subPoi.getLatLonPoint()));
                subPoiMaps.add(subPoiMap);
            }
        }
        map.put("subPois", subPoiMaps);
        return map;
    }

    /** Converts the Dart/iOS field mask to the zero-based PoiSearchV2 mask. */
    private static int androidShowFieldsMask(int mask) {
        if (mask < 0) {
            return PoiSearchV2.ShowFields.ALL;
        }
        // Keep all five extension bits, including PHOTOS (Dart bit 5).
        return (mask >> 1) & 0x1F;
    }

    private static LatLonPoint latLonPoint(Object value) {
        if (!(value instanceof List) || ((List<?>) value).size() < 2) {
            return null;
        }
        List<?> values = (List<?>) value;
        if (!(values.get(0) instanceof Number) || !(values.get(1) instanceof Number)) {
            return null;
        }
        return new LatLonPoint(
                ((Number) values.get(0)).doubleValue(),
                ((Number) values.get(1)).doubleValue());
    }

    private static List<Double> latLonPointToList(LatLonPoint point) {
        if (point == null) {
            return null;
        }
        List<Double> location = new ArrayList<>(2);
        location.add(point.getLatitude());
        location.add(point.getLongitude());
        return location;
    }

    private boolean hasLocationPermission(MethodChannel.Result result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M
                && context.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION)
                != PackageManager.PERMISSION_GRANTED
                && context.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION)
                != PackageManager.PERMISSION_GRANTED) {
            result.error("permission_denied", "请先授予系统定位权限。", null);
            return false;
        }
        LocationManager manager = (LocationManager) context.getSystemService(Context.LOCATION_SERVICE);
        if (manager != null
                && !manager.isProviderEnabled(LocationManager.GPS_PROVIDER)
                && !manager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
            result.error("location_service_disabled", "系统定位服务未开启。", null);
            return false;
        }
        return true;
    }

    private void finishSingle(AMapLocation location, String code, String message) {
        // 回调和超时都汇聚到这里，先清空状态以保证 Flutter Result 只完成一次。
        MethodChannel.Result result;
        Runnable timeout;
        AMapLocationClient client;
        synchronized (singleOperationLock) {
            result = singleResult;
            singleResult = null;
            timeout = singleTimeout;
            singleTimeout = null;
            client = singleClient;
            singleClient = null;
        }
        if (timeout != null) {
            handler.removeCallbacks(timeout);
        }
        if (client != null) {
            destroyLocationClient(client, "single location");
        }
        if (result == null) {
            return;
        }
        if (location != null) {
            result.success(locationToMap(location));
        } else {
            result.error(code, message, null);
        }
    }

    private static Map<String, Object> locationToMap(AMapLocation location) {
        Map<String, Object> map = new HashMap<>();
        map.put("provider", location.getProvider() == null ? "AMap" : location.getProvider());
        List<Double> latLng = new ArrayList<>(2);
        latLng.add(location.getLatitude());
        latLng.add(location.getLongitude());
        map.put("latLng", latLng);
        map.put("accuracy", (double) location.getAccuracy());
        map.put("altitude", location.getAltitude());
        map.put("bearing", (double) location.getBearing());
        map.put("speed", (double) location.getSpeed());
        map.put("time", location.getTime());
        return map;
    }

    private static Map<String, Object> geocodeToMap(GeocodeAddress address) {
        Map<String, Object> map = new HashMap<>();
        LatLonPoint point = address.getLatLonPoint();
        if (point != null) {
            List<Double> location = new ArrayList<>(2);
            location.add(point.getLatitude());
            location.add(point.getLongitude());
            map.put("location", location);
        }
        putIfNotNull(map, "formattedAddress", address.getFormatAddress());
        putIfNotNull(map, "country", address.getCountry());
        putIfNotNull(map, "province", address.getProvince());
        putIfNotNull(map, "city", address.getCity());
        putIfNotNull(map, "district", address.getDistrict());
        putIfNotNull(map, "township", address.getTownship());
        putIfNotNull(map, "neighborhood", address.getNeighborhood());
        putIfNotNull(map, "building", address.getBuilding());
        putIfNotNull(map, "adCode", address.getAdcode());
        putIfNotNull(map, "level", address.getLevel());
        return map;
    }

    private static Map<String, Object> reverseGeocodeToMap(
            RegeocodeAddress address, double latitude, double longitude) {
        Map<String, Object> map = new HashMap<>();
        List<Double> location = new ArrayList<>(2);
        location.add(latitude);
        location.add(longitude);
        map.put("location", location);
        putIfNotNull(map, "formattedAddress", address.getFormatAddress());
        putIfNotNull(map, "country", address.getCountry());
        putIfNotNull(map, "province", address.getProvince());
        putIfNotNull(map, "city", address.getCity());
        putIfNotNull(map, "district", address.getDistrict());
        putIfNotNull(map, "township", address.getTownship());
        putIfNotNull(map, "neighborhood", address.getNeighborhood());
        putIfNotNull(map, "building", address.getBuilding());
        putIfNotNull(map, "adCode", address.getAdCode());
        putIfNotNull(map, "cityCode", address.getCityCode());
        putIfNotNull(map, "townCode", address.getTowncode());
        StreetNumber streetNumber = address.getStreetNumber();
        if (streetNumber != null) {
            putIfNotNull(map, "street", streetNumber.getStreet());
            putIfNotNull(map, "number", streetNumber.getNumber());
        }
        List<PoiItem> pois = address.getPois();
        if (pois != null && !pois.isEmpty()) {
            putIfNotNull(map, "placeName", pois.get(0).getTitle());
        }
        return map;
    }

    private static void putIfNotNull(Map<String, Object> map, String key, Object value) {
        if (value != null) {
            map.put(key, value);
        }
    }

    private static Map<?, ?> arguments(MethodCall call) {
        return call.arguments instanceof Map ? (Map<?, ?>) call.arguments : new HashMap<>();
    }

    private static String stringValue(Object value, String fallback) {
        return value instanceof String ? (String) value : fallback;
    }

    private static String stringOrNull(Object value) {
        if (!(value instanceof String)) {
            return null;
        }
        String string = ((String) value).trim();
        return string.isEmpty() ? null : string;
    }

    private static int intValue(Object value, int fallback) {
        return value instanceof Number ? ((Number) value).intValue() : fallback;
    }

    private static boolean booleanValue(Object value, boolean fallback) {
        return value instanceof Boolean ? (Boolean) value : fallback;
    }

    private static Map<String, String> stringMap(Object value) {
        Map<String, String> output = new HashMap<>();
        if (!(value instanceof Map)) {
            return output;
        }
        for (Map.Entry<?, ?> entry : ((Map<?, ?>) value).entrySet()) {
            if (entry.getKey() instanceof String && entry.getValue() instanceof String) {
                output.put((String) entry.getKey(), (String) entry.getValue());
            }
        }
        return output;
    }

    private static long longValue(Object value, long fallback) {
        return value instanceof Number ? ((Number) value).longValue() : fallback;
    }

    private void stopContinuousLocation() {
        AMapLocationClient client;
        synchronized (singleOperationLock) {
            client = continuousClient;
            continuousClient = null;
        }
        if (client != null) {
            destroyLocationClient(client, "continuous location");
        }
    }

    private void destroyLocationClient(AMapLocationClient client, String operation) {
        try {
            client.stopLocation();
        } catch (Throwable error) {
            LogUtil.e("AMapServicesController", "stop " + operation, error);
        }
        try {
            client.onDestroy();
        } catch (Throwable error) {
            LogUtil.e("AMapServicesController", "destroy " + operation, error);
        }
    }

    private void cancelActiveOperations() {
        stopContinuousLocation();
        finishSingle(null, "privacy_not_agreed", "用户已撤回高德隐私授权。");
        failPendingSearches("privacy_not_agreed", "用户已撤回高德隐私授权。");
    }

    void dispose() {
        disposed = true;
        stopContinuousLocation();
        finishSingle(null, "plugin_disposed", "高德服务控制器已销毁。");
        failPendingSearches("plugin_disposed", "高德服务控制器已销毁。");
        eventSink = null;
    }

    /** Completes pending native searches before the engine/channel is detached. */
    private void failPendingSearches(String code, String message) {
        List<Map.Entry<GeocodeSearch, MethodChannel.Result>> pendingGeocodes;
        List<Map.Entry<PoiSearchV2, MethodChannel.Result>> pendingPois;
        synchronized (searchOperationLock) {
            pendingGeocodes = new ArrayList<>(geocodeSearches.entrySet());
            pendingPois = new ArrayList<>(poiSearches.entrySet());
            geocodeSearches.clear();
            poiSearches.clear();
        }

        for (Map.Entry<GeocodeSearch, MethodChannel.Result> entry : pendingGeocodes) {
            try {
                entry.getKey().setOnGeocodeSearchListener(null);
            } catch (Throwable error) {
                LogUtil.e("AMapServicesController", "detach geocode listener", error);
            }
        }
        for (Map.Entry<PoiSearchV2, MethodChannel.Result> entry : pendingPois) {
            try {
                entry.getKey().setOnPoiSearchListener(null);
            } catch (Throwable error) {
                LogUtil.e("AMapServicesController", "detach POI listener", error);
            }
        }

        if (!pendingGeocodes.isEmpty() || !pendingPois.isEmpty()) {
            // GeocodeSearch and PoiSearchV2 expose no per-request cancellation
            // API. On privacy revocation/dispose all plugin-owned service
            // requests are invalidated, so tear down the SDK async executor
            // after detaching listeners. The SDK recreates it for later calls.
            try {
                ServiceSettings.getInstance().destroyInnerAsynThreadPool();
            } catch (Throwable error) {
                LogUtil.e("AMapServicesController", "destroy search executor", error);
            }
        }

        for (Map.Entry<GeocodeSearch, MethodChannel.Result> entry : pendingGeocodes) {
            entry.getValue().error(code, message, null);
        }
        for (Map.Entry<PoiSearchV2, MethodChannel.Result> entry : pendingPois) {
            entry.getValue().error(code, message, null);
        }
    }

    private MethodChannel.Result takeGeocodeResult(GeocodeSearch search) {
        synchronized (searchOperationLock) {
            return geocodeSearches.remove(search);
        }
    }

    private void removeGeocodeResultAndDetach(GeocodeSearch search) {
        synchronized (searchOperationLock) {
            geocodeSearches.remove(search);
        }
        detachGeocodeListener(search);
    }

    private void detachGeocodeListener(GeocodeSearch search) {
        try {
            search.setOnGeocodeSearchListener(null);
        } catch (Throwable error) {
            LogUtil.e("AMapServicesController", "detach geocode listener", error);
        }
    }

    private MethodChannel.Result takePoiResult(PoiSearchV2 search) {
        synchronized (searchOperationLock) {
            return poiSearches.remove(search);
        }
    }

    private void removePoiResultAndDetach(PoiSearchV2 search) {
        synchronized (searchOperationLock) {
            poiSearches.remove(search);
        }
        detachPoiListener(search);
    }

    private void detachPoiListener(PoiSearchV2 search) {
        try {
            search.setOnPoiSearchListener(null);
        } catch (Throwable error) {
            LogUtil.e("AMapServicesController", "detach POI listener", error);
        }
    }

    @Override
    public void onListen(Object arguments, EventChannel.EventSink events) {
        eventSink = events;
    }

    @Override
    public void onCancel(Object arguments) {
        eventSink = null;
    }
}
