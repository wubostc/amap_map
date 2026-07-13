/**
 * Marker icon JSON renderer tests.
 *
 * @author 913721086@qq.com
 * @date 2026/7/13
 */
package com.amap.flutter.map.overlays.marker;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import android.content.Context;
import android.graphics.Color;
import android.view.View;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.Space;
import android.widget.TextView;

import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.RuntimeEnvironment;

import java.util.HashMap;
import java.util.Map;
import java.util.Collections;

@RunWith(RobolectricTestRunner.class)
public class MarkerIconJsonRendererTest {
    private final Context context = RuntimeEnvironment.getApplication();

    @Test
    public void containerAppliesBoxAndPadding() {
        FrameLayout container = (FrameLayout) MarkerIconJsonRenderer.createView(context, node(
                "container",
                style("backgroundColor", "#FF000000", "padding", 4)
        ));

        assertNotNull(container.getBackground());
        assertEquals(px(4), container.getPaddingLeft());
        assertEquals(px(4), container.getPaddingTop());
    }

    @Test
    public void stackAppliesBoxButNotPadding() {
        FrameLayout stack = (FrameLayout) MarkerIconJsonRenderer.createView(context, node(
                "stack",
                style("backgroundColor", "#FF000000", "padding", 4)
        ));

        assertNotNull(stack.getBackground());
        assertEquals(0, stack.getPaddingLeft());
        assertEquals(0, stack.getPaddingTop());
    }

    @Test
    public void textAppliesBoxAndPadding() {
        TextView text = (TextView) MarkerIconJsonRenderer.createView(context, node(
                "text",
                style("backgroundColor", "#FF000000", "padding", 4)
        ));

        assertNotNull(text.getBackground());
        assertEquals(px(4), text.getPaddingLeft());
        assertEquals(px(4), text.getPaddingTop());
    }

    @Test
    public void rowColumnImageAndSpaceIgnoreUnsupportedBoxStyles() {
        LinearLayout row = (LinearLayout) MarkerIconJsonRenderer.createView(context, node(
                "row",
                style("alignment", "bottom|right", "backgroundColor", "#FF000000", "padding", 4)
        ));
        LinearLayout column = (LinearLayout) MarkerIconJsonRenderer.createView(context, node(
                "column",
                style("backgroundColor", "#FF000000", "padding", 4)
        ));
        ImageView image = (ImageView) MarkerIconJsonRenderer.createView(context, node(
                "image",
                style("backgroundColor", "#FF000000", "padding", 4)
        ));
        View space = MarkerIconJsonRenderer.createView(context, node(
                "space",
                style("backgroundColor", "#FF000000", "padding", 4)
        ));

        assertNull(row.getBackground());
        assertEquals(0, row.getPaddingLeft());
        assertNull(column.getBackground());
        assertEquals(0, column.getPaddingLeft());
        assertNull(image.getBackground());
        assertEquals(0, image.getPaddingLeft());
        assertNull(space.getBackground());
        assertEquals(0, space.getPaddingLeft());
    }

    @Test
    public void containerOnlyReadsTheSingularChildField() {
        Map<String, Object> containerNode = node("container", style());
        containerNode.put("child", node("text", style()));
        containerNode.put("children", Collections.<Object>singletonList(node("space", style())));
        FrameLayout container = (FrameLayout) MarkerIconJsonRenderer.createView(context, containerNode);

        Map<String, Object> stackNode = node("stack", style());
        stackNode.put("child", node("text", style()));
        stackNode.put("children", Collections.<Object>singletonList(node("space", style())));
        FrameLayout stack = (FrameLayout) MarkerIconJsonRenderer.createView(context, stackNode);

        assertEquals(1, container.getChildCount());
        assertEquals(TextView.class, container.getChildAt(0).getClass());
        assertEquals(1, stack.getChildCount());
        assertEquals(Space.class, stack.getChildAt(0).getClass());
    }

    @Test
    public void stackAppliesCanonicalBottomRightAlignment() {
        Map<String, Object> stackNode = node("stack", style(
                "width", 20,
                "height", 20,
                "alignment", "bottom|right"
        ));
        stackNode.put("children", Collections.<Object>singletonList(node(
                "space",
                style("width", 6, "height", 4)
        )));

        MarkerIconJsonRenderer.RenderedIcon rendered = MarkerIconJsonRenderer.renderIcon(context, icon(stackNode));
        View child = ((FrameLayout) rendered.view).getChildAt(0);

        assertEquals(px(14), child.getLeft());
        assertEquals(px(16), child.getTop());
    }

    @Test
    public void colorStylesAcceptOnlySixOrEightDigitHexValues() {
        TextView hexText = (TextView) MarkerIconJsonRenderer.createView(context, node(
                "text",
                style("textColor", "#FF123456")
        ));
        TextView namedText = (TextView) MarkerIconJsonRenderer.createView(context, node(
                "text",
                style("textColor", "red")
        ));
        TextView transparentText = (TextView) MarkerIconJsonRenderer.createView(context, node(
                "text",
                style("textColor", "transparent")
        ));

        assertEquals(Color.rgb(0x12, 0x34, 0x56), hexText.getCurrentTextColor());
        assertEquals(Color.BLACK, namedText.getCurrentTextColor());
        assertEquals(Color.BLACK, transparentText.getCurrentTextColor());
    }

    @Test
    public void iconBitmapIsLimitedToTwoMiB() {
        assertTrue(MarkerIconJsonRenderer.isWithinIconBitmapLimit(512, 1024));
        assertFalse(MarkerIconJsonRenderer.isWithinIconBitmapLimit(513, 1024));
    }

    @Test
    public void oversizedIconUsesTheEmptyFallback() {
        Map<String, Object> stackNode = node("stack", style("width", 600000, "height", 1));

        MarkerIconJsonRenderer.RenderedIcon rendered = MarkerIconJsonRenderer.renderIcon(context, icon(stackNode));

        assertEquals(Space.class, rendered.view.getClass());
    }

    private int px(float logicalValue) {
        return Math.round(logicalValue * context.getResources().getDisplayMetrics().density);
    }

    private static Map<String, Object> icon(Map<String, Object> view) {
        Map<String, Object> icon = new HashMap<>();
        icon.put("view", view);
        return icon;
    }

    private static Map<String, Object> node(String type, Map<String, Object> style) {
        Map<String, Object> node = new HashMap<>();
        node.put("type", type);
        node.put("style", style);
        return node;
    }

    private static Map<String, Object> style(Object... values) {
        Map<String, Object> style = new HashMap<>();
        for (int index = 0; index < values.length; index += 2) {
            style.put((String) values[index], values[index + 1]);
        }
        return style;
    }
}
