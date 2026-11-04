#include "svgelement.h"
#include "svgparserutils.h"
#include "svglayoutstate.h"
#include "svgrenderstate.h"

#include "plutovg.h"
#include <cmath>

namespace lunasvg {

SVGImageElement::SVGImageElement(Document* document)
    : SVGGraphicsElement(document, ElementID::Image)
    , m_x(PropertyID::X, LengthDirection::Horizontal, LengthNegativeMode::Allow, 0.f, LengthUnits::None)
    , m_y(PropertyID::Y, LengthDirection::Vertical, LengthNegativeMode::Allow, 0.f, LengthUnits::None)
    , m_width(PropertyID::Width, LengthDirection::Horizontal, LengthNegativeMode::Forbid, 100.f, LengthUnits::Percent)
    , m_height(PropertyID::Height, LengthDirection::Vertical, LengthNegativeMode::Forbid, 100.f, LengthUnits::Percent)
    , m_preserveAspectRatio(PropertyID::PreserveAspectRatio)
{
    addProperty(m_x);
    addProperty(m_y);
    addProperty(m_width);
    addProperty(m_height);
    addProperty(m_preserveAspectRatio);
}

static Bitmap loadImageResource(const std::string& href)
{
    if(href.compare(0, 5, "data:") == 0) {
        std::string_view input(href);
        auto index = input.find(',', 5);
        if(index == std::string_view::npos)
            return Bitmap();
        input.remove_prefix(index + 1);
        return plutovg_surface_load_from_image_base64(input.data(), input.length());
    }

    return plutovg_surface_load_from_image_file(href.data());
}

void SVGImageElement::parseAttribute(PropertyID id, const std::string& value)
{
    if(id == PropertyID::Href) {
        rootElement()->setNeedsLayout();
        if(!document()->hasExternalContext() || !document()->getExternalContext()->draw_image_helper) {
            m_image = loadImageResource(value);
        }
    } else {
        SVGGraphicsElement::parseAttribute(id, value);
    }
}

Rect SVGImageElement::fillBoundingBox() const
{
    LengthContext lengthContext(this);
    const Rect viewportRect = {
        lengthContext.valueForLength(m_x),
        lengthContext.valueForLength(m_y),
        lengthContext.valueForLength(m_width),
        lengthContext.valueForLength(m_height)
    };

    return viewportRect;
}

Rect SVGImageElement::strokeBoundingBox() const
{
    return fillBoundingBox();
}

void SVGImageElement::render(SVGRenderState& state) const
{
    if(isDisplayNone() || isVisibilityHidden())
        return;
    Rect viewportRect(fillBoundingBox());
    if(viewportRect.isEmpty())
        return;

    if(document()->hasExternalContext() && document()->getExternalContext()->draw_image_helper) {
        const auto& href = getAttribute(PropertyID::Href);
        if(href.empty())
            return;
        external_context_t* xcontext = document()->getExternalContext();

        SVGBlendInfo blendInfo(this);
        SVGRenderState newState(this, state, localTransform());
        const auto& m = newState.currentTransform().matrix();
        double scale_x = std::sqrt(m.a * m.a + m.b * m.b);
        double scale_y = std::sqrt(m.c * m.c + m.d * m.d);
        if(scale_x == 0 || scale_y == 0)
            return;

        double x = viewportRect.x;
        double y = viewportRect.y;
        double width = viewportRect.w;
        double height = viewportRect.h;

        double original_aspect_ratio = 0;
        double image_width = width;
        double image_height = height;
        int original_width;
        int original_height;
        if(xcontext->get_image_size_helper
                && xcontext->get_image_size_helper(xcontext, href.c_str(), original_width, original_height)
                && original_width > 0 && original_height > 0
                && m_preserveAspectRatio.alignType() != SVGPreserveAspectRatio::AlignType::None) {
            original_aspect_ratio = (double)original_width / (double)original_height;
            if(m_preserveAspectRatio.meetOrSlice() == SVGPreserveAspectRatio::MeetOrSlice::Slice) {
                if(width / height > original_aspect_ratio) {
                    image_height = width / original_aspect_ratio;
                } else {
                    image_width = original_aspect_ratio * height;
                }
            } else {
                if(width / height > original_aspect_ratio) {
                    image_width = original_aspect_ratio * height;
                } else {
                    image_height = width / original_aspect_ratio;
                }
            }
        }

        auto image = Canvas::create(0, 0, image_width * scale_x, image_height * scale_y);
        unsigned char* data = plutovg_surface_get_data(image->surface());
        bool drawn = xcontext->draw_image_helper(xcontext, href.c_str(),
                        data, image->width(), image->height(), original_aspect_ratio);
        if(!drawn)
            return;

        Path path;
        path.addRect(x, y, width, height);
        auto viewTransform = m_preserveAspectRatio.getTransform(Rect(0, 0, image_width, image_height), Size(width, height));
        Transform textureTransform(viewTransform);
        textureTransform.postTranslate(x, y);
        textureTransform.scale(1.0 / scale_x, 1.0 / scale_y);

        newState.beginGroup(blendInfo);
        newState->setTexture(*image, TextureType::Plain, 1.f, textureTransform);
        newState->fillPath(path, FillRule::NonZero, newState.currentTransform());
        newState.endGroup(blendInfo);
        return;
    }

    if(m_image.isNull())
        return;
    Rect dstRect(viewportRect);
    Rect srcRect(0, 0, m_image.width(), m_image.height());
    if(srcRect.isEmpty())
        return;
    m_preserveAspectRatio.transformRect(dstRect, srcRect);

    SVGBlendInfo blendInfo(this);
    SVGRenderState newState(this, state, localTransform());
    newState.beginGroup(blendInfo);
    newState->drawImage(m_image, dstRect, srcRect, newState.currentTransform());
    newState.endGroup(blendInfo);
}

} // namespace lunasvg
