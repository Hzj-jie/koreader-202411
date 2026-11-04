#ifndef XTEXTELEMENT_H
#define XTEXTELEMENT_H

#include "xtspanelement.h"

namespace lunasvg {

class SVGTextElement final : public SVGGraphicsElement
{
public:
    SVGTextElement(Document* document);

    void clip(SVGRenderState& state) const;
    Rect fillBoundingBox() const override { return m_fillBoundingBox; }
    Rect strokeBoundingBox() const override { return m_strokeBoundingBox; }
    void layout(SVGLayoutState& state) override;
    void render(SVGRenderState& state) const override;

private:
    std::vector<std::unique_ptr<XTxtGlyphGroup>> m_groups;
    Rect m_fillBoundingBox = Rect::Empty;
    Rect m_strokeBoundingBox = Rect::Empty;
};

} // namespace lunasvg

#endif // XTEXTELEMENT_H
