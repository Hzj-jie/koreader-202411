#include "xtspanelement.h"
#include "svggeometryelement.h"
#include "svglayoutstate.h"

#include <cmath>
#include <cstdio>
#include <cstring>

namespace lunasvg {

SVGTSpanElement::SVGTSpanElement(Document* document, ElementID id)
    : SVGGraphicsElement(document, id)
{
}

void SVGTSpanElement::layoutElement(const SVGLayoutState& state)
{
    SVGGraphicsElement::layoutElement(state);
    m_fill = getPaintServer(state.fill(), state.fill_opacity());
    m_stroke = getPaintServer(state.stroke(), state.stroke_opacity());
    m_strokeData = getStrokeData(state);
    m_fill_rule = state.fill_rule();
    m_clip_rule = state.clip_rule();
}

void SVGTSpanElement::addCurrentGroup(std::vector<std::unique_ptr<XTxtGlyphGroup>>& groups, text_state_t& text_state)
{
    if(text_state.current_group == nullptr)
        return;
    if(text_state.current_group->children.empty()) {
        text_state.current_group = nullptr;
        return;
    }
    double dx = text_state.current_end_x - text_state.current_start_x;
    double dy = text_state.current_end_y - text_state.current_start_y;
    if(text_state.current_length_adjust != XLengthAdjust::None) {
        if(dx > 0) {
            if(text_state.current_length_adjust == XLengthAdjust::SpacingAndGlyphs) {
                double scale_x = text_state.current_adjust_text_length / dx;
                text_state.current_group->transform.scale(scale_x, 1);
            } else {
                double total_to_add = text_state.current_adjust_text_length - dx;
                int nb_adjustable = 0;
                bool is_first = true;
                for(const auto& glyph : text_state.current_group->children) {
                    if(glyph.is_decoration)
                        continue;
                    if(!is_first && glyph.can_adjust_from_previous)
                        nb_adjustable++;
                    is_first = false;
                }
                if(nb_adjustable > 0) {
                    double to_add = total_to_add / nb_adjustable;
                    double cumulative_added = 0;
                    bool is_first = true;
                    for(auto& glyph : text_state.current_group->children) {
                        if(glyph.is_decoration)
                            continue;
                        if(!is_first && glyph.can_adjust_from_previous) {
                            cumulative_added += to_add;
                        }
                        glyph.transform.translate(cumulative_added, 0);
                        is_first = false;
                    }
                }
            }
            dx = text_state.current_adjust_text_length;
        }
    }
    if(text_state.current_text_anchor != TextAnchor::Start && text_state.current_started) {
        if(text_state.current_text_anchor == TextAnchor::Middle) {
            dx = dx / 2;
            dy = dy / 2;
        }
        text_state.current_start_x -= dx;
        text_state.current_start_y -= dy;
    }
    if(text_state.is_vertical_rl) {
        text_state.current_group->transform.postMultiply(Transform::rotated(90, 0, 0));
    }
    text_state.current_group->transform.postMultiply(Transform::translated(text_state.current_start_x, text_state.current_start_y));
    groups.push_back(std::move(text_state.current_group));
    text_state.current_group = nullptr;
    text_state.current_length_adjust = XLengthAdjust::None;
}

void SVGTSpanElement::layoutText(SVGLayoutState& parentState, std::vector<std::unique_ptr<XTxtGlyphGroup>>& groups, text_state_t& text_state)
{
    SVGLayoutState state(parentState, this);
    layoutElement(state);

    if(!document()->hasExternalContext() || !document()->getExternalContext()->text_to_paths_helper)
        return;

    if(isDisplayNone())
        return;

    LengthContext lengthContext(this);

    bool absolute_position_reset = false;
    if(hasAttribute(PropertyID::X)) {
        SVGLengthList xs(PropertyID::X, LengthDirection::Horizontal, LengthNegativeMode::Allow);
        xs.parse(getAttribute(PropertyID::X));
        if(!xs.values().empty()) {
            text_state.cursor_x = lengthContext.valueForLength(xs.values()[0], LengthDirection::Horizontal);
            absolute_position_reset = true;
        }
    }
    if(hasAttribute(PropertyID::Y)) {
        SVGLengthList ys(PropertyID::Y, LengthDirection::Vertical, LengthNegativeMode::Allow);
        ys.parse(getAttribute(PropertyID::Y));
        if(!ys.values().empty()) {
            text_state.cursor_y = lengthContext.valueForLength(ys.values()[0], LengthDirection::Vertical);
            absolute_position_reset = true;
        }
    }
    if(hasAttribute(PropertyID::Dx)) {
        SVGLengthList dxs(PropertyID::Dx, LengthDirection::Horizontal, LengthNegativeMode::Allow);
        dxs.parse(getAttribute(PropertyID::Dx));
        if(!dxs.values().empty()) {
            if(text_state.is_vertical_rl)
                text_state.cursor_y -= lengthContext.valueForLength(dxs.values()[0], LengthDirection::Vertical);
            else
                text_state.cursor_x += lengthContext.valueForLength(dxs.values()[0], LengthDirection::Horizontal);
        }
    }
    if(hasAttribute(PropertyID::Dy)) {
        SVGLengthList dys(PropertyID::Dy, LengthDirection::Vertical, LengthNegativeMode::Allow);
        dys.parse(getAttribute(PropertyID::Dy));
        if(!dys.values().empty()) {
            if(text_state.is_vertical_rl)
                text_state.cursor_x += lengthContext.valueForLength(dys.values()[0], LengthDirection::Horizontal);
            else
                text_state.cursor_y += lengthContext.valueForLength(dys.values()[0], LengthDirection::Vertical);
        }
    }

    SVGAngle rotate(PropertyID::Rotate);
    rotate.parse(findInheritedAttribute(this, PropertyID::Rotate));

    Point text_path_start;
    Point text_path_next;
    if(id() == ElementID::TextPath) {
        Path text_path;
        Transform text_path_transform;
        if(hasAttribute(PropertyID::Path)) {
            const auto& path_str = getAttribute(PropertyID::Path);
            text_path.parse(path_str.data(), path_str.length());
        } else if(hasAttribute(PropertyID::Href)) {
            std::string_view href(getAttribute(PropertyID::Href));
            if(!href.empty() && href.front() == '#') {
                auto ref = rootElement()->getElementById(href.substr(1));
                if(ref != nullptr && ref->isGeometryElement()) {
                    auto gref = static_cast<const SVGGeometryElement*>(ref);
                    text_path = gref->path();
                    text_path_transform = gref->localTransform();
                }
            }
        }
        PathIterator it(text_path);
        std::array<Point, 3> pts;
        if(it.isDone())
            return;
        it.currentSegment(pts);
        text_path_start = text_path_transform.mapPoint(pts[0]);
        it.next();
        if(it.isDone())
            return;
        it.currentSegment(pts);
        text_path_next = text_path_transform.mapPoint(pts[0]);
        absolute_position_reset = true;
    }

    auto prev_text_anchor = text_state.text_anchor;
    if(hasAttribute(PropertyID::Text_Anchor)) {
        const auto& text_anchor = getAttribute(PropertyID::Text_Anchor);
        if(text_anchor == "end")
            text_state.text_anchor = TextAnchor::End;
        else if(text_anchor == "middle")
            text_state.text_anchor = TextAnchor::Middle;
        else if(text_anchor == "start")
            text_state.text_anchor = TextAnchor::Start;
    }

    if(absolute_position_reset) {
        addCurrentGroup(groups, text_state);
    }
    if(text_state.current_group == nullptr) {
        text_state.current_group = std::make_unique<XTxtGlyphGroup>();
        text_state.current_started = false;
        text_state.current_text_anchor = text_state.text_anchor;
    }

    if(absolute_position_reset) {
        if(hasAttribute(PropertyID::TextLength)) {
            Length text_length(0, LengthUnits::None);
            if(text_length.parse(getAttribute(PropertyID::TextLength), LengthNegativeMode::Forbid)) {
                text_state.current_adjust_text_length = lengthContext.valueForLength(text_length, LengthDirection::Horizontal);
                if(text_state.current_adjust_text_length != 0) {
                    const auto& length_adjust = getAttribute(PropertyID::LengthAdjust);
                    if(length_adjust == "spacingAndGlyphs")
                        text_state.current_length_adjust = XLengthAdjust::SpacingAndGlyphs;
                    else
                        text_state.current_length_adjust = XLengthAdjust::Spacing;
                }
            }
        }
    }

    if(id() == ElementID::TextPath) {
        text_state.cursor_x = text_path_start.x;
        text_state.cursor_y = text_path_start.y;
        Point slope{text_path_next.x - text_path_start.x, text_path_next.y - text_path_start.y};
        auto angle = 180.0 * std::atan2(slope.y, slope.x) / 3.14159265358979323846;
        text_state.current_group->transform.rotate(angle, 0, 0);
        text_state.current_length_adjust = XLengthAdjust::None;
        text_state.text_anchor = TextAnchor::Start;
    }

    auto prev_is_pre = text_state.is_pre;
    bool space_prop_found = false;
    if(hasAttribute(PropertyID::White_Space)) {
        const auto& white_space = getAttribute(PropertyID::White_Space);
        if(white_space == "normal" || white_space == "nowrap" || white_space == "pre-line") {
            text_state.is_pre = false;
            space_prop_found = true;
        } else if(white_space == "pre" || white_space == "pre-wrap" || white_space == "break-spaces") {
            text_state.is_pre = true;
            space_prop_found = true;
        }
    }
    if(!space_prop_found && hasAttribute(PropertyID::XMLSpace)) {
        const auto& xml_space = getAttribute(PropertyID::XMLSpace);
        if(xml_space == "default")
            text_state.is_pre = false;
        else if(xml_space == "preserve")
            text_state.is_pre = true;
    }

    const auto& source_text = getAttribute(PropertyID::_Text_Internal);
    std::string text;
    if(text_state.is_pre) {
        for(char const& c : source_text) {
            if(c == ' ' || c == '\t' || c == '\n' || c == '\r') {
                text += ' ';
            } else {
                text += c;
            }
        }
    } else {
        bool last_was_space = text_state.last_was_space;
        for(char const& c : source_text) {
            if(c == ' ' || c == '\t' || c == '\n' || c == '\r') {
                if(!last_was_space) {
                    text += ' ';
                    last_was_space = true;
                }
            } else {
                text += c;
                last_was_space = false;
            }
        }
    }

    double fontsize = font_size();

    if(!text.empty() && fontsize > 0) {
        external_font_spec_t font_spec;
        font_spec.size = fontsize;

        std::string font_family = findInheritedAttribute(this, PropertyID::Font_Family);
        font_spec.family = font_family.c_str();

        font_spec.italic = false;
        const auto& style = findInheritedAttribute(this, PropertyID::Font_Style);
        if(style == "italic" || style == "oblique") {
            font_spec.italic = true;
        }

        font_spec.weight = 400;
        const auto& weight = findInheritedAttribute(this, PropertyID::Font_Weight);
        if(weight == "normal") {
            font_spec.weight = 400;
        } else if(weight == "bold") {
            font_spec.weight = 700;
        } else if(weight == "lighter") {
            font_spec.weight = 100;
        } else if(weight == "bolder") {
            font_spec.weight = 900;
        } else if(!weight.empty()) {
            Length w(0, LengthUnits::None);
            if(w.parse(weight, LengthNegativeMode::Forbid)) {
                int wt = (w.units() == LengthUnits::Percent) ? int(w.value()) : int(w.value());
                if(wt >= 100 && wt <= 900)
                    font_spec.weight = wt;
            }
        }

        font_spec.features = 0;
        const auto& variant = findInheritedAttribute(this, PropertyID::Font_Variant);
        if(variant == "small-caps") {
            font_spec.features = 0x00000100;
        }

        std::string lang = findInheritedAttribute(this, PropertyID::Lang);
        if(!lang.empty()) {
            font_spec.lang = lang.c_str();
        }

        double letter_spacing = 0;
        const auto& letterspacing_str = findInheritedAttribute(this, PropertyID::Letter_Spacing);
        if(!letterspacing_str.empty()) {
            Length letterspacing(0, LengthUnits::None);
            if(letterspacing.parse(letterspacing_str, LengthNegativeMode::Allow) && letterspacing.value() != 0.f) {
                letter_spacing = lengthContext.valueForLength(letterspacing, LengthDirection::Horizontal);
            }
        }

        bool draw_text_decoration = false;
        double text_decoration_start_x = text_state.cursor_x;

        auto add_glyph_callback = tspan_path_callback_t([&](const char* path_d, double advance_x, double advance_y,
                                                            bool can_adjust_from_previous, unsigned int base_char) {
            Path path;
            if(path_d && *path_d)
                path.parse(path_d, std::strlen(path_d));
            if(letter_spacing != 0 && text_state.current_started && can_adjust_from_previous) {
                text_state.cursor_x += letter_spacing;
            }
            if(base_char == ' ' && !text_state.is_pre) {
                text_state.last_was_space = true;
            } else {
                text_state.last_was_space = false;
                draw_text_decoration = true;
                if(!text_state.current_started) {
                    text_state.current_started = true;
                    text_state.current_start_x = text_state.cursor_x;
                    text_state.current_start_y = text_state.cursor_y;
                    text_state.current_end_x = text_state.cursor_x;
                    text_state.current_end_y = text_state.cursor_y;
                }
                if(!path.isEmpty()) {
                    XTxtGlyphShape shape;
                    shape.path = std::move(path);
                    shape.can_adjust_from_previous = can_adjust_from_previous;
                    shape.transform = Transform::translated(text_state.cursor_x - text_state.current_start_x,
                                                            text_state.cursor_y - text_state.current_start_y);
                    if(rotate.value() != 0) {
                        shape.transform.rotate(rotate.value(), 0, 0);
                    }
                    shape.element = this;
                    text_state.current_group->children.push_back(std::move(shape));
                }
            }
            text_state.cursor_x += advance_x;
            text_state.cursor_y += advance_y;
            if(text_state.current_started && !text_state.last_was_space) {
                text_state.current_end_x = text_state.cursor_x;
                text_state.current_end_y = text_state.cursor_y;
            }
        });

        external_context_t* xcontext = document()->getExternalContext();
        xcontext->text_to_paths_helper(xcontext, text.c_str(), &font_spec, add_glyph_callback);

        if(draw_text_decoration) {
            const auto& text_decoration = findInheritedAttribute(this, PropertyID::Text_Decoration);
            double thickness = fontsize / 28;
            double dy = 0;
            if(text_decoration == "underline") {
                dy = fontsize * 1 / 10;
            } else if(text_decoration == "overline") {
                dy = -fontsize * 7 / 8;
            } else if(text_decoration == "line-through") {
                dy = -fontsize * 1 / 4;
            } else {
                draw_text_decoration = false;
            }
            if(draw_text_decoration) {
                XTxtGlyphShape shape;
                shape.is_decoration = true;
                double x_start = text_decoration_start_x - text_state.current_start_x;
                double w = text_state.cursor_x - text_decoration_start_x;
                double y = text_state.cursor_y - text_state.current_start_y + dy - thickness / 2;
                shape.path.addRect(x_start, y, w, thickness);
                shape.element = this;
                text_state.current_group->children.push_back(std::move(shape));
            }
        }
    }

    for(const auto& child : children()) {
        auto element = toSVGElement(child);
        if(element && (element->id() == ElementID::Tspan || element->id() == ElementID::TextPath)) {
            static_cast<SVGTSpanElement*>(element)->layoutText(state, groups, text_state);
        } else if(element) {
            printf("UNEXPECTED non-tspan <tspan> child\n");
        }
    }

    text_state.text_anchor = prev_text_anchor;
    text_state.is_pre = prev_is_pre;
}

} // namespace lunasvg
