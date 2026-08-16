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
import com.amap.api.maps.MapsInitializer;
import com.amap.api.services.core.AMapException;
import com.amap.api.services.core.LatLonPoint;
import com.amap.api.services.core.PoiItem;
import com.amap.api.services.core.ServiceSettings;
import com.amap.api.services.geocoder.GeocodeAddress;
import com.amap.api.services.geocoder.GeocodeQuery;
import com.amap.api.services.geocoder.GeocodeResult;
import com.amap.api.services.geocoder.GeocodeSearch;
import com.amap.api.services.geocoder.RegeocodeAddress;
import com.amap.api.services.geocoder.RegeocodeQuery;
import com.amap.api.services.geocoder.RegeocodeResult;
import com.amap.api.services.geocoder.StreetNumber;
import com.amap.flutter.map2.utils.ConvertUtil;

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
    private EventChannel.EventSink eventSink;
    // 单次和连续定位使用不同实例，避免单次请求中断正在运行的连续定位。
    private AMapLocationClient continuousClient;
    private AMapLocationClient singleClient;
    private MethodChannel.Result singleResult;
    private Runnable singleTimeout;
    // SDK 的搜索回调是异步的，请求完成前需要强引用 GeocodeSearch。
    private final Map<GeocodeSearch, MethodChannel.Result> geocodeSearches = new LinkedHashMap<>();

    AMapServicesController(Context context) {
        Context applicationContext = context.getApplicationContext();
        this.context = applicationContext == null ? context : applicationContext;
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
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
        if (singleResult != null) {
            result.error("location_busy", "已有单次定位请求正在执行。", null);
            return;
        }
        try {
            singleResult = result;
            singleClient = new AMapLocationClient(context);
            singleClient.setLocationOption(locationOptions(options, true));
            singleClient.setLocationListener(location -> {
                if (singleResult == null) {
                    return;
                }
                if (location != null && location.getErrorCode() == AMapLocation.LOCATION_SUCCESS) {
                    finishSingle(location, null, null);
                } else {
                    String message = location == null ? "定位 SDK 未返回位置。"
                            : location.getErrorInfo() + " (" + location.getErrorCode() + ")";
                    finishSingle(null, "location_failed", message);
                }
            });
            long timeout = longValue(options.get("timeout"), 10000L);
            singleTimeout = () -> finishSingle(null, "location_timeout", "定位超时。");
            handler.postDelayed(singleTimeout, timeout);
            singleClient.startLocation();
        } catch (Exception exception) {
            finishSingle(null, "location_failed", exception.getMessage());
        }
    }

    private void startLocation(Map<?, ?> options, MethodChannel.Result result) {
        if (!hasLocationPermission(result)) {
            return;
        }
        stopContinuousLocation();
        try {
            continuousClient = new AMapLocationClient(context);
            continuousClient.setLocationOption(locationOptions(options, false));
            continuousClient.setLocationListener(new AMapLocationListener() {
                @Override
                public void onLocationChanged(AMapLocation location) {
                    if (eventSink == null) {
                        return;
                    }
                    if (location != null && location.getErrorCode() == AMapLocation.LOCATION_SUCCESS) {
                        eventSink.success(locationToMap(location));
                    } else {
                        String message = location == null ? "定位 SDK 未返回位置。"
                                : location.getErrorInfo() + " (" + location.getErrorCode() + ")";
                        eventSink.error("location_failed", message, null);
                    }
                }
            });
            continuousClient.startLocation();
            result.success(null);
        } catch (Exception exception) {
            stopContinuousLocation();
            result.error("location_failed", exception.getMessage(), null);
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
        try {
            GeocodeSearch search = new GeocodeSearch(context);
            geocodeSearches.put(search, result);
            search.setOnGeocodeSearchListener(new GeocodeSearch.OnGeocodeSearchListener() {
                @Override
                public void onRegeocodeSearched(RegeocodeResult ignored, int code) {
                    // 当前搜索实例只处理正向地理编码。
                }

                @Override
                public void onGeocodeSearched(GeocodeResult geocodeResult, int code) {
                    MethodChannel.Result pendingResult = geocodeSearches.remove(search);
                    if (pendingResult == null) {
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
                            output.add(geocodeToMap(address));
                        }
                    }
                    pendingResult.success(output);
                }
            });
            String city = values.get("city") instanceof String ? (String) values.get("city") : "";
            search.getFromLocationNameAsyn(new GeocodeQuery(((String) addressValue).trim(), city));
        } catch (AMapException exception) {
            result.error("geocode_failed", exception.getErrorMessage(), exception.getErrorCode());
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
        try {
            GeocodeSearch search = new GeocodeSearch(context);
            geocodeSearches.put(search, result);
            search.setOnGeocodeSearchListener(new GeocodeSearch.OnGeocodeSearchListener() {
                @Override
                public void onRegeocodeSearched(RegeocodeResult regeocodeResult, int code) {
                    MethodChannel.Result pendingResult = geocodeSearches.remove(search);
                    if (pendingResult == null) {
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
                }

                @Override
                public void onGeocodeSearched(GeocodeResult ignored, int code) {
                    // 当前搜索实例只处理逆地理编码。
                }
            });
            RegeocodeQuery query = new RegeocodeQuery(
                    new LatLonPoint(latitude, longitude), radius, GeocodeSearch.AMAP);
            search.getFromLocationAsyn(query);
        } catch (AMapException exception) {
            result.error("reverse_geocode_failed",
                    exception.getErrorMessage(), exception.getErrorCode());
        }
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
        MethodChannel.Result result = singleResult;
        singleResult = null;
        if (singleTimeout != null) {
            handler.removeCallbacks(singleTimeout);
            singleTimeout = null;
        }
        if (singleClient != null) {
            singleClient.stopLocation();
            singleClient.onDestroy();
            singleClient = null;
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

    private static long longValue(Object value, long fallback) {
        return value instanceof Number ? ((Number) value).longValue() : fallback;
    }

    private void stopContinuousLocation() {
        if (continuousClient != null) {
            continuousClient.stopLocation();
            continuousClient.onDestroy();
            continuousClient = null;
        }
    }

    private void cancelActiveOperations() {
        stopContinuousLocation();
        if (singleResult != null) {
            finishSingle(null, "privacy_not_agreed", "用户已撤回高德隐私授权。");
        }
        for (MethodChannel.Result result : new ArrayList<>(geocodeSearches.values())) {
            result.error("privacy_not_agreed", "用户已撤回高德隐私授权。", null);
        }
        geocodeSearches.clear();
    }

    void dispose() {
        stopContinuousLocation();
        singleResult = null;
        if (singleTimeout != null) {
            handler.removeCallbacks(singleTimeout);
            singleTimeout = null;
        }
        if (singleClient != null) {
            singleClient.stopLocation();
            singleClient.onDestroy();
            singleClient = null;
        }
        geocodeSearches.clear();
        eventSink = null;
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
