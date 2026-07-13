/**
 * Marker icon JSON renderer.
 *
 * @author 913721086@qq.com
 * @date 2026/7/13
 */
package com.amap.flutter.map.overlays.marker;

import android.content.Context;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.text.TextUtils;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.Space;
import android.widget.TextView;

import com.amap.flutter.map.utils.ConvertUtil;

import java.util.Collections;
import java.util.List;
import java.util.Locale;
import java.util.Map;

public final class MarkerIconJsonRenderer {
    private static final long MAX_ICON_BITMAP_BYTES = 2L * 1024L * 1024L;
    private static final int ARGB_BYTES_PER_PIXEL = 4;

    private MarkerIconJsonRenderer() {
    }

    public static final class RenderedIcon {
        public final View view;

        RenderedIcon(View view) {
            this.view = view;
        }
    }

    public static RenderedIcon renderIcon(Context context, Map<String, Object> iconMap) {
        Map<String, Object> safeIcon = iconMap == null ? Collections.<String, Object>emptyMap() : iconMap;
        Map<String, Object> viewNode = asMap(safeIcon.get("view"));

        if (viewNode.isEmpty() && safeIcon.containsKey("type")) {
            viewNode = safeIcon;
        }

        View view = viewNode.isEmpty() || !isRootLayoutNode(viewNode)
                ? createFallbackView(context)
                : createView(context, viewNode);
        applyRootLayoutParams(context, view, viewNode);
        measureAndLayout(view);

        if (!isWithinIconBitmapLimit(view.getMeasuredWidth(), view.getMeasuredHeight())) {
            view = createFallbackView(context);
            measureAndLayout(view);
        }

        return new RenderedIcon(view);
    }

    static boolean isWithinIconBitmapLimit(int widthInPixels, int heightInPixels) {
        if (widthInPixels <= 0 || heightInPixels <= 0) {
            return true;
        }
        return (long) widthInPixels * heightInPixels
                <= MAX_ICON_BITMAP_BYTES / ARGB_BYTES_PER_PIXEL;
    }

    public static View createView(Context context, Map<String, Object> node) {
        String type = getString(node, "type", "stack").toLowerCase(Locale.US);
        Map<String, Object> style = asMap(node.get("style"));
        View view;

        switch (type) {
            case "row": {
                LinearLayout row = new LinearLayout(context);
                row.setOrientation(LinearLayout.HORIZONTAL);
                applyRowStyle(row, style);
                addChildren(context, row, node);
                view = row;
                break;
            }
            case "column": {
                LinearLayout column = new LinearLayout(context);
                column.setOrientation(LinearLayout.VERTICAL);
                applyColumnStyle(column, style);
                addChildren(context, column, node);
                view = column;
                break;
            }
            case "stack": {
                FrameLayout frame = new FrameLayout(context);
                frame.setClipChildren(false);
                frame.setClipToPadding(false);
                applyStackStyle(context, frame, style);
                addChildren(context, frame, node);
                view = frame;
                break;
            }
            case "container": {
                FrameLayout frame = new FrameLayout(context);
                frame.setClipChildren(false);
                frame.setClipToPadding(false);
                applyContainerStyle(context, frame, style);
                addChildren(context, frame, node);
                view = frame;
                break;
            }
            case "text": {
                TextView textView = new TextView(context);
                applyTextProps(context, textView, node, style);
                applyTextStyle(context, textView, style);
                view = textView;
                break;
            }
            case "image": {
                ImageView imageView = new ImageView(context);
                applyImageProps(context, imageView, node, style);
                applyImageStyle(imageView, style);
                view = imageView;
                break;
            }
            case "space": {
                Space space = new Space(context);
                applySpaceStyle(space, style);
                view = space;
                break;
            }
            default: {
                Space fallback = new Space(context);
                view = fallback;
                break;
            }
        }

        return view;
    }

    private static boolean isRootLayoutNode(Map<String, Object> node) {
        String type = getString(node, "type", "").toLowerCase(Locale.US);
        return "row".equals(type) || "column".equals(type) || "stack".equals(type) || "container".equals(type);
    }

    private static boolean supportsRootSize(Map<String, Object> node) {
        String type = getString(node, "type", "").toLowerCase(Locale.US);
        return "stack".equals(type) || "container".equals(type);
    }

    private static boolean supportsExplicitSize(Map<String, Object> node) {
        String type = getString(node, "type", "").toLowerCase(Locale.US);
        return "container".equals(type)
                || "stack".equals(type)
                || "text".equals(type)
                || "image".equals(type)
                || "space".equals(type);
    }

    private static void addChildren(Context context, ViewGroup parent, Map<String, Object> node) {
        Map<String, Object> parentStyle = asMap(node.get("style"));
        Map<String, Object> singleChildNode = asMap(node.get("child"));
        if (isContainerNode(node) && !singleChildNode.isEmpty()) {
            View child = createView(context, singleChildNode);
            Map<String, Object> childStyle = asMap(singleChildNode.get("style"));
            parent.addView(child, createChildLayoutParams(context, parent, childStyle, parentStyle, singleChildNode));
        }

        if (isContainerNode(node)) {
            return;
        }

        List<?> children = asList(node.get("children"));
        for (Object childObj : children) {
            Map<String, Object> childNode = asMap(childObj);
            if (childNode.isEmpty()) {
                continue;
            }

            View child = createView(context, childNode);
            Map<String, Object> childStyle = asMap(childNode.get("style"));
            parent.addView(child, createChildLayoutParams(context, parent, childStyle, parentStyle, childNode));
        }
    }

    private static boolean isContainerNode(Map<String, Object> node) {
        return "container".equals(getString(node, "type", "").toLowerCase(Locale.US));
    }

    private static void applyTextProps(Context context, TextView textView, Map<String, Object> node, Map<String, Object> style) {
        Map<String, Object> props = asMap(node.get("props"));
        textView.setText(getStringFromNode(node, props, "text", ""));

        String textColor = getString(style, "textColor", null);
        if (textColor != null) {
            textView.setTextColor(parseColor(textColor, Color.BLACK));
        }

        if (style.containsKey("textSize")) {
            textView.setTextSize(TypedValue.COMPLEX_UNIT_SP, getFloat(style, "textSize", 14f));
        }

        int gravity = readContentGravity(style, Integer.MIN_VALUE);
        if (gravity != Integer.MIN_VALUE) {
            textView.setGravity(gravity);
        }

        if (style.containsKey("maxLines")) {
            textView.setMaxLines(getInt(style, "maxLines", Integer.MAX_VALUE));
        }

        if (style.containsKey("minLines")) {
            textView.setMinLines(getInt(style, "minLines", 0));
        }

        if (getBoolean(style, "singleLine", false)) {
            textView.setMaxLines(1);
        }

        String ellipsize = getString(style, "ellipsize", null);
        if (ellipsize != null) {
            textView.setEllipsize(parseEllipsize(ellipsize));
        }

        if (style.containsKey("includeFontPadding")) {
            textView.setIncludeFontPadding(getBoolean(style, "includeFontPadding", true));
        }

        int typefaceStyle = parseTypefaceStyle(
                getString(style, "textStyle", null),
                getString(style, "fontWeight", null)
        );
        if (typefaceStyle != Typeface.NORMAL) {
            textView.setTypeface(textView.getTypeface(), typefaceStyle);
        }
    }

    private static void applyImageProps(Context context, ImageView imageView, Map<String, Object> node, Map<String, Object> style) {
        Map<String, Object> props = asMap(node.get("props"));
        Object src = getValueFromNode(node, props, "src");
        applyImageSource(context, imageView, src);
        imageView.setScaleType(ImageView.ScaleType.FIT_CENTER);
    }

    private static void applyRowStyle(LinearLayout layout, Map<String, Object> style) {
        applyLinearLayoutAlignment(layout, style);
    }

    private static void applyColumnStyle(LinearLayout layout, Map<String, Object> style) {
        applyLinearLayoutAlignment(layout, style);
    }

    private static void applyLinearLayoutAlignment(LinearLayout layout, Map<String, Object> style) {
        int gravity = readContentGravity(style, Integer.MIN_VALUE);
        if (gravity != Integer.MIN_VALUE) {
            layout.setGravity(gravity);
        }
    }

    private static void applyStackStyle(Context context, FrameLayout frame, Map<String, Object> style) {
        applyBoxStyle(context, frame, style);
    }

    private static void applyContainerStyle(Context context, FrameLayout frame, Map<String, Object> style) {
        applyBoxStyle(context, frame, style);
        applyPadding(context, frame, style);
    }

    private static void applyTextStyle(Context context, TextView textView, Map<String, Object> style) {
        applyBoxStyle(context, textView, style);
        applyPadding(context, textView, style);
    }

    private static void applyImageStyle(ImageView imageView, Map<String, Object> style) {
        // Image dimensions and margins are assigned through the parent layout params.
    }

    private static void applySpaceStyle(Space space, Map<String, Object> style) {
        // Space dimensions are assigned through the parent layout params.
    }

    private static void applyBoxStyle(Context context, View view, Map<String, Object> style) {
        if (style == null || style.isEmpty()) {
            return;
        }

        boolean hasBackground = style.containsKey("backgroundColor")
                || style.containsKey("borderColor")
                || style.containsKey("borderWidth")
                || style.containsKey("radius");

        if (!hasBackground) {
            return;
        }

        GradientDrawable drawable = new GradientDrawable();
        drawable.setShape(GradientDrawable.RECTANGLE);

        String backgroundColor = getString(style, "backgroundColor", null);
        drawable.setColor(backgroundColor == null ? Color.TRANSPARENT : parseColor(backgroundColor, Color.TRANSPARENT));

        if (style.containsKey("radius")) {
            drawable.setCornerRadius(dp(context, getFloat(style, "radius", 0f)));
        }

        int borderWidth = style.containsKey("borderWidth") ? dp(context, getFloat(style, "borderWidth", 0f)) : 0;
        String borderColor = getString(style, "borderColor", null);
        if (borderWidth > 0 && borderColor != null) {
            drawable.setStroke(borderWidth, parseColor(borderColor, Color.TRANSPARENT));
        }

        view.setBackground(drawable);
    }

    private static void applyPadding(Context context, View view, Map<String, Object> style) {
        if (style == null || style.isEmpty()) {
            return;
        }

        Edges padding = readEdges(context, style.get("padding"));
        if (padding != null) {
            view.setPadding(padding.left, padding.top, padding.right, padding.bottom);
        }
    }

    private static void applyImageSource(Context context, ImageView imageView, Object src) {
        if (!(src instanceof List)) {
            return;
        }

        imageView.setImageBitmap(ConvertUtil.toBitmapFromImageSource(src));
    }

    private static ViewGroup.LayoutParams createChildLayoutParams(
            Context context,
            ViewGroup parent,
            Map<String, Object> style,
            Map<String, Object> parentStyle,
            Map<String, Object> childNode) {
        boolean canSize = supportsExplicitSize(childNode);
        int width = canSize ? readSize(context, style.get("width"), ViewGroup.LayoutParams.WRAP_CONTENT)
                : ViewGroup.LayoutParams.WRAP_CONTENT;
        int height = canSize ? readSize(context, style.get("height"), ViewGroup.LayoutParams.WRAP_CONTENT)
                : ViewGroup.LayoutParams.WRAP_CONTENT;
        Edges margin = readEdges(context, style.get("margin"));

        if (parent instanceof LinearLayout) {
            LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(width, height);
            applyMargins(params, margin);
            return params;
        }

        if (parent instanceof FrameLayout) {
            FrameLayout.LayoutParams params = new FrameLayout.LayoutParams(width, height);
            int gravity = readGravity(parentStyle.get("alignment"), Gravity.NO_GRAVITY);
            params.gravity = gravity;
            applyMargins(params, margin);
            return params;
        }

        ViewGroup.MarginLayoutParams params = new ViewGroup.MarginLayoutParams(width, height);
        applyMargins(params, margin);
        return params;
    }

    private static void applyRootLayoutParams(Context context, View view, Map<String, Object> node) {
        Map<String, Object> style = asMap(node.get("style"));
        boolean canSize = supportsRootSize(node);
        int width = canSize ? readSize(context, style.get("width"), ViewGroup.LayoutParams.WRAP_CONTENT)
                : ViewGroup.LayoutParams.WRAP_CONTENT;
        int height = canSize ? readSize(context, style.get("height"), ViewGroup.LayoutParams.WRAP_CONTENT)
                : ViewGroup.LayoutParams.WRAP_CONTENT;
        view.setLayoutParams(new ViewGroup.LayoutParams(width, height));
    }

    private static void applyMargins(ViewGroup.MarginLayoutParams params, Edges margin) {
        if (margin != null) {
            params.setMargins(margin.left, margin.top, margin.right, margin.bottom);
        }
    }

    private static void measureAndLayout(View view) {
        ViewGroup.LayoutParams params = view.getLayoutParams();
        int width = params == null ? ViewGroup.LayoutParams.WRAP_CONTENT : params.width;
        int height = params == null ? ViewGroup.LayoutParams.WRAP_CONTENT : params.height;
        view.measure(createRootMeasureSpec(width), createRootMeasureSpec(height));
        int measuredWidth = Math.max(1, view.getMeasuredWidth());
        int measuredHeight = Math.max(1, view.getMeasuredHeight());
        view.layout(0, 0, measuredWidth, measuredHeight);
    }

    private static View createFallbackView(Context context) {
        Space space = new Space(context);
        space.setLayoutParams(new ViewGroup.LayoutParams(dp(context, 1f), dp(context, 1f)));
        return space;
    }

    private static int readSize(Context context, Object value, int defValue) {
        if (value == null) {
            return defValue;
        }

        if (value instanceof Number) {
            return dp(context, ((Number) value).floatValue());
        }

        return defValue;
    }

    private static int createRootMeasureSpec(int layoutSize) {
        if (layoutSize >= 0) {
            return View.MeasureSpec.makeMeasureSpec(layoutSize, View.MeasureSpec.EXACTLY);
        }
        return View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED);
    }

    private static int readContentGravity(Map<String, Object> style, int defValue) {
        if (style == null || style.isEmpty()) {
            return defValue;
        }
        return readGravity(style.get("alignment"), defValue);
    }

    private static Edges readEdges(Context context, Object raw) {
        if (raw == null) {
            return null;
        }

        if (raw instanceof Number || raw instanceof String) {
            int all = readSize(context, raw, 0);
            return new Edges(all, all, all, all);
        }

        if (raw instanceof Map) {
            Map<String, Object> map = asMap(raw);
            int left = readSize(context, firstNonNull(map.get("left"), map.get("horizontal")), 0);
            int top = readSize(context, firstNonNull(map.get("top"), map.get("vertical")), 0);
            int right = readSize(context, firstNonNull(map.get("right"), map.get("horizontal")), 0);
            int bottom = readSize(context, firstNonNull(map.get("bottom"), map.get("vertical")), 0);
            return new Edges(left, top, right, bottom);
        }

        List<?> list = asList(raw);
        if (list.isEmpty()) {
            return null;
        }

        if (list.size() == 1) {
            int all = readSize(context, list.get(0), 0);
            return new Edges(all, all, all, all);
        }

        if (list.size() == 2) {
            int horizontal = readSize(context, list.get(0), 0);
            int vertical = readSize(context, list.get(1), 0);
            return new Edges(horizontal, vertical, horizontal, vertical);
        }

        if (list.size() == 3) {
            int left = readSize(context, list.get(0), 0);
            int vertical = readSize(context, list.get(1), 0);
            int right = readSize(context, list.get(2), 0);
            return new Edges(left, vertical, right, vertical);
        }

        int left = readSize(context, list.get(0), 0);
        int top = readSize(context, list.get(1), 0);
        int right = readSize(context, list.get(2), 0);
        int bottom = readSize(context, list.get(3), 0);
        return new Edges(left, top, right, bottom);
    }

    private static int readGravity(Object raw, int defValue) {
        if (!(raw instanceof String)) {
            return defValue;
        }

        String value = ((String) raw).trim().toLowerCase(Locale.US);
        if (value.isEmpty()) {
            return defValue;
        }

        switch (value) {
            case "center":
                return Gravity.CENTER;
            case "top|left":
                return Gravity.TOP | Gravity.LEFT;
            case "top|right":
                return Gravity.TOP | Gravity.RIGHT;
            case "bottom|left":
                return Gravity.BOTTOM | Gravity.LEFT;
            case "bottom|right":
                return Gravity.BOTTOM | Gravity.RIGHT;
            case "top|center":
                return Gravity.TOP | Gravity.CENTER_HORIZONTAL;
            case "bottom|center":
                return Gravity.BOTTOM | Gravity.CENTER_HORIZONTAL;
            case "center|left":
                return Gravity.CENTER_VERTICAL | Gravity.LEFT;
            case "center|right":
                return Gravity.CENTER_VERTICAL | Gravity.RIGHT;
            default:
                return defValue;
        }
    }

    private static TextUtils.TruncateAt parseEllipsize(String value) {
        String normalized = value.toLowerCase(Locale.US);
        if ("start".equals(normalized)) {
            return TextUtils.TruncateAt.START;
        }
        if ("middle".equals(normalized)) {
            return TextUtils.TruncateAt.MIDDLE;
        }
        return TextUtils.TruncateAt.END;
    }

    private static int parseTypefaceStyle(String textStyle, String fontWeight) {
        boolean bold = false;
        boolean italic = false;

        if (textStyle != null) {
            String value = textStyle.toLowerCase(Locale.US);
            bold = value.contains("bold");
            italic = value.contains("italic");
        }

        if (fontWeight != null) {
            String value = fontWeight.toLowerCase(Locale.US);
            bold = bold || "bold".equals(value) || "700".equals(value) || "800".equals(value) || "900".equals(value);
        }

        if (bold && italic) {
            return Typeface.BOLD_ITALIC;
        }
        if (bold) {
            return Typeface.BOLD;
        }
        if (italic) {
            return Typeface.ITALIC;
        }
        return Typeface.NORMAL;
    }

    private static int parseColor(String value, int defValue) {
        if (value == null) {
            return defValue;
        }

        String normalized = value.trim();
        if (!normalized.startsWith("#")) {
            return defValue;
        }

        try {
            return Color.parseColor(normalized);
        } catch (IllegalArgumentException ignored) {
            return defValue;
        }
    }

    private static int dp(Context context, float value) {
        return Math.round(value * context.getResources().getDisplayMetrics().density);
    }

    private static Object firstNonNull(Object a, Object b) {
        return a != null ? a : b;
    }

    private static String getStringFromNode(Map<String, Object> node, Map<String, Object> props, String key, String defValue) {
        Object value = getValueFromNode(node, props, key);
        return value == null ? defValue : String.valueOf(value);
    }

    private static Object getValueFromNode(Map<String, Object> node, Map<String, Object> props, String key) {
        if (node.containsKey(key)) {
            return node.get(key);
        }
        return props.get(key);
    }

    private static String getString(Map<String, Object> map, String key, String defValue) {
        if (map == null || !map.containsKey(key) || map.get(key) == null) {
            return defValue;
        }
        return String.valueOf(map.get(key));
    }

    private static int getInt(Map<String, Object> map, String key, int defValue) {
        if (map == null || !map.containsKey(key)) {
            return defValue;
        }
        Object value = map.get(key);
        if (value instanceof Number) {
            return ((Number) value).intValue();
        }
        try {
            return Integer.parseInt(String.valueOf(value));
        } catch (RuntimeException ignored) {
            return defValue;
        }
    }

    private static float getFloat(Map<String, Object> map, String key, float defValue) {
        if (map == null || !map.containsKey(key)) {
            return defValue;
        }
        return asFloat(map.get(key), defValue);
    }

    private static float asFloat(Object value, float defValue) {
        if (value instanceof Number) {
            return ((Number) value).floatValue();
        }
        try {
            return Float.parseFloat(String.valueOf(value));
        } catch (RuntimeException ignored) {
            return defValue;
        }
    }

    private static boolean getBoolean(Map<String, Object> map, String key, boolean defValue) {
        if (map == null || !map.containsKey(key)) {
            return defValue;
        }
        Object value = map.get(key);
        if (value instanceof Boolean) {
            return (Boolean) value;
        }
        if (value instanceof Number) {
            return ((Number) value).intValue() != 0;
        }
        String text = String.valueOf(value).toLowerCase(Locale.US);
        return "true".equals(text) || "1".equals(text) || "yes".equals(text);
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> asMap(Object value) {
        if (value instanceof Map) {
            return (Map<String, Object>) value;
        }
        return Collections.emptyMap();
    }

    private static List<?> asList(Object value) {
        if (value instanceof List) {
            return (List<?>) value;
        }
        return Collections.emptyList();
    }

    private static final class Edges {
        final int left;
        final int top;
        final int right;
        final int bottom;

        Edges(int left, int top, int right, int bottom) {
            this.left = left;
            this.top = top;
            this.right = right;
            this.bottom = bottom;
        }
    }
}
