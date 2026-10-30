#ifndef XTSPANELEMENT_H
#define XTSPANELEMENT_H

#include "svgelement.h"
#include "svglayoutstate.h"

#include <memory>
#include <vector>

namespace lunasvg {

enum class XLengthAdjust
{
    None,
    Spacing,
    SpacingAndGlyphs,
};

class SVGTSpanElement;

struct XTxtGlyphShape
{
    Path path;
    Transform transform;
    const SVGTSpanElement* element = nullptr;
    bool can_adjust_from_previous = true;
    bool is_decoration = false;
};

struct XTxtGlyphGroup
{
    Transform transform;
    std::vector<XTxtGlyphShape> children;
};

typedef struct {
    double cursor_x;
    double cursor_y;
    double current_start_x;
    double current_start_y;
    double current_end_x;
    double current_end_y;
    bool current_started;
    bool last_was_space;
    bool is_pre;
    bool is_vertical_rl;
    TextAnchor text_anchor;
    TextAnchor current_text_anchor;
    XLengthAdjust current_length_adjust;
    double current_adjust_text_length;
    std::unique_ptr<XTxtGlyphGroup> current_group;
} text_state_t;

class SVGTSpanElement final : public SVGGraphicsElement
{
public:
    SVGTSpanElement(Document* document, ElementID id = ElementID::Tspan);

    const SVGPaintServer& fill() const { return m_fill; }
    const SVGPaintServer& stroke() const { return m_stroke; }
    const StrokeData& strokeData() const { return m_strokeData; }
    FillRule fill_rule() const { return m_fill_rule; }
    FillRule clip_rule() const { return m_clip_rule; }

    static void addCurrentGroup(std::vector<std::unique_ptr<XTxtGlyphGroup>>& groups, text_state_t& text_state);

    void layoutElement(const SVGLayoutState& state) override;
    void layoutText(SVGLayoutState& state, std::vector<std::unique_ptr<XTxtGlyphGroup>>& groups, text_state_t& text_state);

private:
    SVGPaintServer m_fill;
    SVGPaintServer m_stroke;
    StrokeData m_strokeData;
    FillRule m_fill_rule = FillRule::NonZero;
    FillRule m_clip_rule = FillRule::NonZero;
};

inline const std::string& findInheritedAttribute(const SVGElement* element, PropertyID id)
{
    for(auto cur = element; cur != nullptr; cur = cur->parentElement()) {
        if(cur->hasAttribute(id))
            return cur->getAttribute(id);
    }
    static const std::string empty;
    return empty;
}

} // namespace lunasvg

#endif // XTSPANELEMENT_H
