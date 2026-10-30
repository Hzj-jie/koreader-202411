#include "xtextelement.h"
#include "xtspanelement.h"
#include "svglayoutstate.h"
#include "svgrenderstate.h"

#include <cstdio>

namespace lunasvg {

SVGTextElement::SVGTextElement(Document* document)
    : SVGGraphicsElement(document, ElementID::Text)
{
}

void SVGTextElement::layout(SVGLayoutState& state)
{
    SVGLayoutState newState(state, this);
    SVGGraphicsElement::layoutElement(newState);

    m_groups.clear();
    m_fillBoundingBox = Rect::Empty;
    m_strokeBoundingBox = Rect::Empty;

    if(!document()->hasExternalContext() || !document()->getExternalContext()->text_to_paths_helper)
        return;

    if(isDisplayNone())
        return;

    if(hasAttribute(PropertyID::_Text_Internal)) {
        printf("UNEXPECTED <text> text string: %s\n", getAttribute(PropertyID::_Text_Internal).c_str());
    }

    text_state_t text_state;
    text_state.cursor_x = 0;
    text_state.cursor_y = 0;
    text_state.current_group = nullptr;
    text_state.current_started = false;
    text_state.current_length_adjust = XLengthAdjust::None;
    text_state.last_was_space = true;
    text_state.is_pre = false;
    text_state.is_vertical_rl = false;

    LengthContext lengthContext(this);
    if(hasAttribute(PropertyID::X)) {
        SVGLengthList xs(PropertyID::X, LengthDirection::Horizontal, LengthNegativeMode::Allow);
        xs.parse(getAttribute(PropertyID::X));
        if(!xs.values().empty()) {
            text_state.cursor_x = lengthContext.valueForLength(xs.values()[0], LengthDirection::Horizontal);
        }
    }
    if(hasAttribute(PropertyID::Y)) {
        SVGLengthList ys(PropertyID::Y, LengthDirection::Vertical, LengthNegativeMode::Allow);
        ys.parse(getAttribute(PropertyID::Y));
        if(!ys.values().empty()) {
            text_state.cursor_y = lengthContext.valueForLength(ys.values()[0], LengthDirection::Vertical);
        }
    }

    const auto& text_anchor = findInheritedAttribute(this, PropertyID::Text_Anchor);
    if(text_anchor == "end")
        text_state.text_anchor = TextAnchor::End;
    else if(text_anchor == "middle")
        text_state.text_anchor = TextAnchor::Middle;
    else
        text_state.text_anchor = TextAnchor::Start;

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

    const auto& writing_mode = findInheritedAttribute(this, PropertyID::Writing_Mode);
    if(writing_mode == "tb" || writing_mode == "tb-rl" || writing_mode == "vertical-rl") {
        text_state.is_vertical_rl = true;
    }

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
        if(xml_space == "default") {
            text_state.is_pre = false;
            space_prop_found = true;
        } else if(xml_space == "preserve") {
            text_state.is_pre = true;
            space_prop_found = true;
        }
    }
    if(!space_prop_found) {
        const auto& white_space = findInheritedAttribute(this, PropertyID::White_Space);
        if(white_space == "normal" || white_space == "nowrap" || white_space == "pre-line") {
            text_state.is_pre = false;
            space_prop_found = true;
        } else if(white_space == "pre" || white_space == "pre-wrap" || white_space == "break-spaces") {
            text_state.is_pre = true;
            space_prop_found = true;
        }
    }
    if(!space_prop_found) {
        const auto& xml_space = findInheritedAttribute(this, PropertyID::XMLSpace);
        if(xml_space == "default") {
            text_state.is_pre = false;
        } else if(xml_space == "preserve") {
            text_state.is_pre = true;
        }
    }

    for(const auto& child : children()) {
        auto element = toSVGElement(child);
        if(element && (element->id() == ElementID::Tspan || element->id() == ElementID::TextPath)) {
            static_cast<SVGTSpanElement*>(element)->layoutText(newState, m_groups, text_state);
        } else if(element) {
            printf("UNEXPECTED non-tspan <text> child\n");
        }
    }

    SVGTSpanElement::addCurrentGroup(m_groups, text_state);

    auto fillBoundingBox = Rect::Invalid;
    auto strokeBoundingBox = Rect::Invalid;
    for(const auto& group : m_groups) {
        for(const auto& glyph : group->children) {
            Transform t = group->transform * glyph.transform;
            Rect fillBox = t.mapRect(glyph.path.boundingRect());
            fillBoundingBox.unite(fillBox);
            Rect strokeBox = fillBox;
            if(glyph.element && glyph.element->stroke().isRenderable()) {
                const auto& sd = glyph.element->strokeData();
                float capLimit = sd.lineWidth() / 2.f;
                if(sd.lineCap() == LineCap::Square)
                    capLimit *= PLUTOVG_SQRT2;
                float joinLimit = sd.lineWidth() / 2.f;
                if(sd.lineJoin() == LineJoin::Miter)
                    joinLimit *= sd.miterLimit();
                strokeBox.inflate(std::max(capLimit, joinLimit));
            }
            strokeBoundingBox.unite(strokeBox);
        }
    }
    if(fillBoundingBox.isValid())
        m_fillBoundingBox = fillBoundingBox;
    if(strokeBoundingBox.isValid())
        m_strokeBoundingBox = strokeBoundingBox;
}

void SVGTextElement::clip(SVGRenderState& state) const
{
    if(isDisplayNone())
        return;
    for(const auto& group : m_groups) {
        for(const auto& glyph : group->children) {
            if(!glyph.element || glyph.element->isVisibilityHidden())
                continue;
            Transform t = state.currentTransform() * localTransform() * group->transform * glyph.transform;
            state->clipPath(glyph.path, glyph.element->clip_rule(), t);
        }
    }
}

void SVGTextElement::render(SVGRenderState& state) const
{
    if(isDisplayNone() || m_groups.empty())
        return;
    if(state.mode() == SVGRenderMode::Clipping) {
        clip(state);
        return;
    }

    SVGBlendInfo blendInfo(this);
    SVGRenderState newState(this, state, localTransform());
    newState.beginGroup(blendInfo);

    for(const auto& group : m_groups) {
        Transform groupTransform = newState.currentTransform() * group->transform;
        for(const auto& glyph : group->children) {
            const SVGTSpanElement* el = glyph.element;
            if(!el || el->isVisibilityHidden() || (!el->fill().isRenderable() && !el->stroke().isRenderable()))
                continue;
            SVGBlendInfo glyphBlend(el);
            SVGRenderState glyphState(el, &newState, groupTransform * glyph.transform, newState.mode(), newState.canvas());
            glyphState.beginGroup(glyphBlend);
            if(el->fill().applyPaint(glyphState))
                glyphState->fillPath(glyph.path, el->fill_rule(), glyphState.currentTransform());
            if(el->stroke().applyPaint(glyphState))
                glyphState->strokePath(glyph.path, el->strokeData(), glyphState.currentTransform());
            glyphState.endGroup(glyphBlend);
        }
    }

    newState.endGroup(blendInfo);
}

} // namespace lunasvg
