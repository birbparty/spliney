#define _RIVE_INTERNAL_

#include "cg_factory.hpp"
#include "cg_renderer.hpp"
#include "rive/animation/keyed_object.hpp"
#include "rive/animation/keyed_property.hpp"
#include "rive/animation/linear_animation.hpp"
#include "rive/artboard.hpp"
#include "rive/bones/bone.hpp"
#include "rive/bones/root_bone.hpp"
#include "rive/bones/skin.hpp"
#include "rive/bones/tendon.hpp"
#include "rive/bones/weight.hpp"
#include "rive/component.hpp"
#include "rive/constraints/constraint.hpp"
#include "rive/constraints/ik_constraint.hpp"
#include "rive/constraints/targeted_constraint.hpp"
#include "rive/constraints/transform_constraint.hpp"
#include "rive/core/field_types/core_bool_type.hpp"
#include "rive/core/field_types/core_color_type.hpp"
#include "rive/core/field_types/core_double_type.hpp"
#include "rive/core/field_types/core_string_type.hpp"
#include "rive/core/field_types/core_uint_type.hpp"
#include "rive/file.hpp"
#include "rive/generated/core_registry.hpp"
#include "rive/renderer.hpp"
#include "rive/shapes/contour_mesh_vertex.hpp"
#include "rive/shapes/mesh.hpp"
#include "rive/shapes/paint/fill.hpp"
#include "rive/shapes/paint/solid_color.hpp"
#include "rive/transform_component.hpp"
#include "utils/factory_utils.hpp"
#include "utils/lite_rtti.hpp"

#include <CommonCrypto/CommonDigest.h>
#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <ImageIO/ImageIO.h>

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <map>
#include <memory>
#include <sstream>
#include <string>
#include <vector>

namespace {
constexpr int kWidth = 960;
constexpr int kHeight = 540;
constexpr uint8_t kBackground[4] = {245, 247, 250, 255};

struct Options {
  std::string asset;
  std::string output;
  std::string referenceDir;
  std::string runtimeSha;
};

struct Roi {
  int left = kWidth;
  int top = kHeight;
  int right = -1;
  int bottom = -1;
  size_t foregroundPixels = 0;
};

struct Frame {
  std::string filename;
  std::string sha;
  std::vector<uint8_t> pixels;
  Roi roi;
};

std::string jsonEscape(const std::string &value) {
  std::ostringstream out;
  for (unsigned char c : value) {
    switch (c) {
    case '\\':
      out << "\\\\";
      break;
    case '"':
      out << "\\\"";
      break;
    case '\n':
      out << "\\n";
      break;
    case '\r':
      out << "\\r";
      break;
    case '\t':
      out << "\\t";
      break;
    default:
      if (c < 0x20)
        out << "\\u" << std::hex << std::setw(4) << std::setfill('0')
            << static_cast<int>(c) << std::dec;
      else
        out << c;
    }
  }
  return out.str();
}

bool parseOptions(int argc, const char *argv[], Options *options) {
  for (int index = 1; index < argc; ++index) {
    const std::string key = argv[index];
    if (++index >= argc)
      return false;
    const std::string value = argv[index];
    if (key == "--asset")
      options->asset = value;
    else if (key == "--output")
      options->output = value;
    else if (key == "--reference-dir")
      options->referenceDir = value;
    else if (key == "--runtime-sha")
      options->runtimeSha = value;
    else
      return false;
  }
  return !options->asset.empty() && !options->output.empty() &&
         !options->referenceDir.empty() && !options->runtimeSha.empty();
}

bool readBytes(const std::string &path, std::vector<uint8_t> *bytes) {
  std::ifstream input(path, std::ios::binary);
  if (!input)
    return false;
  input.seekg(0, std::ios::end);
  const auto length = input.tellg();
  if (length < 0)
    return false;
  input.seekg(0, std::ios::beg);
  bytes->resize(static_cast<size_t>(length));
  return bytes->empty() ||
         static_cast<bool>(
             input.read(reinterpret_cast<char *>(bytes->data()), length));
}

std::string sha256(const uint8_t *bytes, size_t length) {
  unsigned char digest[CC_SHA256_DIGEST_LENGTH];
  CC_SHA256(bytes, static_cast<CC_LONG>(length), digest);
  std::ostringstream out;
  out << std::hex << std::setfill('0');
  for (unsigned char value : digest)
    out << std::setw(2) << static_cast<unsigned>(value);
  return out.str();
}

std::string sha256(const std::vector<uint8_t> &bytes) {
  return sha256(bytes.data(), bytes.size());
}

std::string sha256File(const std::string &path) {
  std::vector<uint8_t> bytes;
  return readBytes(path, &bytes) ? sha256(bytes) : std::string();
}

struct ImageInfo {
  const rive::RenderImage *image = nullptr;
  std::vector<uint8_t> encoded;
  size_t encodedBytes = 0;
  std::string encodedSha;
  int width = 0;
  int height = 0;
};

class OracleFactory : public rive::CGFactory {
public:
  std::vector<ImageInfo> images;

  rive::rcp<rive::RenderImage>
  decodeImage(rive::Span<const uint8_t> encoded) override {
    auto image = rive::CGFactory::decodeImage(encoded);
    images.push_back({image.get(),
                      std::vector<uint8_t>(encoded.begin(), encoded.end()),
                      encoded.size(), sha256(encoded.data(), encoded.size()),
                      image ? image->width() : 0, image ? image->height() : 0});
    return image;
  }

  int imageIndex(const rive::RenderImage *image) const {
    for (size_t index = 0; index < images.size(); ++index)
      if (images[index].image == image)
        return static_cast<int>(index);
    return -1;
  }
};

void writeMatrix(std::ostream &out, const rive::Mat2D &value) {
  out << '[';
  for (int index = 0; index < 6; ++index) {
    if (index)
      out << ',';
    out << value[index];
  }
  out << ']';
}

struct DrawCommand {
  std::string kind;
  int imageIndex = -1;
  rive::Mat2D transform;
  float opacity = 1;
  uint32_t sampler = 0;
  uint32_t blendMode = 0;
  std::vector<rive::Vec2D> vertices;
  std::vector<rive::Vec2D> uvs;
  std::vector<uint16_t> indices;
  const rive::RenderImage *image = nullptr;
  rive::ImageSampler imageSampler;
  rive::BlendMode blend = rive::BlendMode::srcOver;
  rive::rcp<rive::RenderBuffer> vertexBuffer;
  rive::rcp<rive::RenderBuffer> uvBuffer;
  rive::rcp<rive::RenderBuffer> indexBuffer;
};

class RecordingRenderer : public rive::Renderer {
  struct State {
    rive::Mat2D transform;
    float opacity = 1;
  };
  const OracleFactory &m_factory;
  std::vector<State> m_stack = {State()};

public:
  std::vector<DrawCommand> commands;
  explicit RecordingRenderer(const OracleFactory &factory)
      : m_factory(factory) {}

  void save() override { m_stack.push_back(m_stack.back()); }
  void restore() override {
    if (m_stack.size() <= 1) {
      std::cerr << "recording renderer: unbalanced restore\n";
      std::exit(10);
    }
    m_stack.pop_back();
  }
  void transform(const rive::Mat2D &value) override {
    m_stack.back().transform *= value;
  }
  void drawPath(rive::RenderPath *, rive::RenderPaint *) override {
    DrawCommand command;
    command.kind = "path";
    command.transform = m_stack.back().transform;
    command.opacity = m_stack.back().opacity;
    commands.push_back(std::move(command));
  }
  void clipPath(rive::RenderPath *) override {
    DrawCommand command;
    command.kind = "clip";
    command.transform = m_stack.back().transform;
    commands.push_back(std::move(command));
  }
  void drawImage(const rive::RenderImage *image, rive::ImageSampler sampler,
                 rive::BlendMode blend, float opacity) override {
    DrawCommand command;
    command.kind = "image";
    command.image = image;
    command.imageSampler = sampler;
    command.blend = blend;
    command.imageIndex = m_factory.imageIndex(image);
    command.transform = m_stack.back().transform;
    command.opacity = opacity * m_stack.back().opacity;
    command.sampler = sampler.asKey();
    command.blendMode = static_cast<uint32_t>(blend);
    commands.push_back(std::move(command));
  }
  void drawImageMesh(const rive::RenderImage *image, rive::ImageSampler sampler,
                     rive::rcp<rive::RenderBuffer> vertices,
                     rive::rcp<rive::RenderBuffer> uvs,
                     rive::rcp<rive::RenderBuffer> indices,
                     uint32_t vertexCount, uint32_t indexCount,
                     rive::BlendMode blend, float opacity) override {
    auto vertexData =
        rive::lite_rtti_cast<rive::DataRenderBuffer *>(vertices.get());
    auto uvData = rive::lite_rtti_cast<rive::DataRenderBuffer *>(uvs.get());
    auto indexData =
        rive::lite_rtti_cast<rive::DataRenderBuffer *>(indices.get());
    if (!vertexData || !uvData || !indexData) {
      std::cerr << "recording renderer: unexpected render buffer type\n";
      std::exit(10);
    }
    DrawCommand command;
    command.kind = "imageMesh";
    command.image = image;
    command.imageSampler = sampler;
    command.blend = blend;
    command.vertexBuffer = vertices;
    command.uvBuffer = uvs;
    command.indexBuffer = indices;
    command.imageIndex = m_factory.imageIndex(image);
    command.transform = m_stack.back().transform;
    command.opacity = opacity * m_stack.back().opacity;
    command.sampler = sampler.asKey();
    command.blendMode = static_cast<uint32_t>(blend);
    command.vertices.assign(vertexData->vecs(),
                            vertexData->vecs() + vertexCount);
    command.uvs.assign(uvData->vecs(), uvData->vecs() + vertexCount);
    command.indices.assign(indexData->u16s(), indexData->u16s() + indexCount);
    commands.push_back(std::move(command));
  }
  void modulateOpacity(float value) override {
    m_stack.back().opacity *= value;
  }
  bool balanced() const { return m_stack.size() == 1; }
};

void settleScene(rive::Scene *scene, double seconds, bool bounded) {
  scene->advanceAndApply(0);
  if (!bounded) {
    if (seconds > 0)
      scene->advanceAndApply(static_cast<float>(seconds));
    return;
  }
  double remaining = seconds;
  while (remaining > 1e-9) {
    const double step = std::min(0.1, remaining);
    scene->advanceAndApply(static_cast<float>(step));
    remaining -= step;
  }
}

void writePropertyValue(std::ostream &out, rive::Core *object, uint32_t key) {
  const int type = rive::CoreRegistry::propertyFieldId(key);
  if (type == rive::CoreUintType::id)
    out << rive::CoreRegistry::getUint(object, key);
  else if (type == rive::CoreStringType::id)
    out << '"' << jsonEscape(rive::CoreRegistry::getString(object, key)) << '"';
  else if (type == rive::CoreDoubleType::id)
    out << rive::CoreRegistry::getDouble(object, key);
  else if (type == rive::CoreColorType::id)
    out << rive::CoreRegistry::getColor(object, key);
  else if (type == rive::CoreBoolType::id)
    out << (rive::CoreRegistry::getBool(object, key) ? "true" : "false");
  else
    out << "null";
}

void writeDrawCommands(std::ostream &out,
                       const std::vector<DrawCommand> &commands) {
  out << '[';
  for (size_t commandIndex = 0; commandIndex < commands.size();
       ++commandIndex) {
    if (commandIndex)
      out << ',';
    const auto &command = commands[commandIndex];
    out << "{\"index\":" << commandIndex << ",\"kind\":\"" << command.kind
        << "\",\"imageIndex\":" << command.imageIndex << ",\"transform\":";
    writeMatrix(out, command.transform);
    out << ",\"opacity\":" << command.opacity
        << ",\"sampler\":" << command.sampler
        << ",\"blendMode\":" << command.blendMode;
    if (command.kind == "imageMesh") {
      out << ",\"vertices\":[";
      for (size_t index = 0; index < command.vertices.size(); ++index) {
        if (index)
          out << ',';
        out << '[' << command.vertices[index].x << ','
            << command.vertices[index].y << ']';
      }
      out << "],\"uvs\":[";
      for (size_t index = 0; index < command.uvs.size(); ++index) {
        if (index)
          out << ',';
        out << '[' << command.uvs[index].x << ',' << command.uvs[index].y
            << ']';
      }
      out << "],\"indices\":[";
      for (size_t index = 0; index < command.indices.size(); ++index) {
        if (index)
          out << ',';
        out << command.indices[index];
      }
      out << ']';
    }
    out << '}';
  }
  out << ']';
}

void writeState(std::ostream &out, rive::File *file,
                const OracleFactory &factory, size_t animationIndex,
                double seconds, bool bounded) {
  auto artboard = file->artboardAt(0);
  auto scene = artboard->animationAt(animationIndex);
  if (!artboard || !scene) {
    std::cerr << "oracle state: scene construction failed\n";
    std::exit(10);
  }
  settleScene(scene.get(), seconds, bounded);

  out << "{\"seconds\":" << seconds << ",\"stepMode\":\""
      << (bounded ? "bounded-positive" : "single-advance") << "\",";
  out << "\"transforms\":[";
  bool first = true;
  for (auto *object : artboard->objects()) {
    if (!object->is<rive::Bone>() && !object->is<rive::RootBone>())
      continue;
    auto *component = object->as<rive::TransformComponent>();
    if (!first)
      out << ',';
    first = false;
    out << "{\"objectId\":" << artboard->idOf(object)
        << ",\"typeKey\":" << object->coreType() << ",\"name\":\""
        << jsonEscape(component->name()) << "\",\"world\":";
    writeMatrix(out, component->worldTransform());
    out << '}';
  }
  out << "],\"constraints\":[";
  first = true;
  for (auto *object : artboard->objects()) {
    if (!object->is<rive::IKConstraint>() &&
        !object->is<rive::TransformConstraint>())
      continue;
    auto *constraint = object->as<rive::Constraint>();
    auto *targeted = object->as<rive::TargetedConstraint>();
    auto *parent = constraint->parent();
    auto *target = artboard->resolve(targeted->targetId());
    if (!first)
      out << ',';
    first = false;
    out << "{\"objectId\":" << artboard->idOf(object)
        << ",\"typeKey\":" << object->coreType() << ",\"name\":\""
        << jsonEscape(constraint->name())
        << "\",\"strength\":" << constraint->strength()
        << ",\"parentId\":" << artboard->idOf(parent)
        << ",\"targetId\":" << targeted->targetId();
    if (parent && parent->is<rive::TransformComponent>()) {
      out << ",\"parentWorld\":";
      writeMatrix(out,
                  parent->as<rive::TransformComponent>()->worldTransform());
    }
    if (target && target->is<rive::TransformComponent>()) {
      out << ",\"targetWorld\":";
      writeMatrix(out,
                  target->as<rive::TransformComponent>()->worldTransform());
    }
    out << '}';
  }
  out << "],\"solverObjects\":[";
  first = true;
  for (auto *object : artboard->objects()) {
    if (!object->is<rive::Skin>() && !object->is<rive::Tendon>() &&
        !object->is<rive::Weight>() && !object->is<rive::Mesh>() &&
        !object->is<rive::ContourMeshVertex>())
      continue;
    auto *component = object->as<rive::Component>();
    if (!first)
      out << ',';
    first = false;
    out << "{\"objectId\":" << artboard->idOf(object)
        << ",\"typeKey\":" << object->coreType() << ",\"parentId\":"
        << (component->parent() ? artboard->idOf(component->parent()) : 0);
    if (object->is<rive::Skin>()) {
      auto *skin = object->as<rive::Skin>();
      out << ",\"kind\":\"skin\",\"bind\":[" << skin->xx() << ',' << skin->yx()
          << ',' << skin->xy() << ',' << skin->yy() << ',' << skin->tx() << ','
          << skin->ty() << ']';
    } else if (object->is<rive::Tendon>()) {
      auto *tendon = object->as<rive::Tendon>();
      out << ",\"kind\":\"tendon\",\"boneId\":" << tendon->boneId()
          << ",\"inverseBind\":";
      writeMatrix(out, tendon->inverseBind());
    } else if (object->is<rive::Weight>()) {
      auto *weight = object->as<rive::Weight>();
      out << ",\"kind\":\"weight\",\"values\":" << weight->values()
          << ",\"indices\":" << weight->indices() << ",\"translation\":["
          << weight->translation().x << ',' << weight->translation().y << ']';
    } else if (object->is<rive::Mesh>()) {
      auto *mesh = object->as<rive::Mesh>();
      out << ",\"kind\":\"mesh\",\"skinId\":"
          << (mesh->skin() ? artboard->idOf(mesh->skin()) : 0);
    } else {
      auto *vertex = object->as<rive::ContourMeshVertex>();
      out << ",\"kind\":\"contourMeshVertex\",\"position\":[" << vertex->x()
          << ',' << vertex->y() << "],\"uv\":[" << vertex->u() << ','
          << vertex->v() << ']';
    }
    out << '}';
  }
  out << "],\"animatedProperties\":[";
  first = true;
  const auto *animation = file->artboard(0)->animation(animationIndex);
  for (size_t objectIndex = 0; objectIndex < animation->numKeyedObjects();
       ++objectIndex) {
    const auto *keyedObject = animation->getObject(objectIndex);
    auto *target = artboard->resolve(keyedObject->objectId());
    for (size_t propertyIndex = 0;
         propertyIndex < keyedObject->numKeyedProperties(); ++propertyIndex) {
      const auto *property = keyedObject->getProperty(propertyIndex);
      if (!first)
        out << ',';
      first = false;
      out << "{\"objectId\":" << keyedObject->objectId()
          << ",\"propertyKey\":" << property->propertyKey() << ",\"value\":";
      writePropertyValue(out, target, property->propertyKey());
      out << '}';
    }
  }
  out << "],\"visibleFill\":[";
  first = true;
  for (auto *object : artboard->objects()) {
    if (!object->is<rive::SolidColor>() && !object->is<rive::Fill>())
      continue;
    if (!first)
      out << ',';
    first = false;
    out << "{\"objectId\":" << artboard->idOf(object)
        << ",\"typeKey\":" << object->coreType();
    if (object->is<rive::SolidColor>())
      out << ",\"color\":" << object->as<rive::SolidColor>()->colorValue();
    if (object->is<rive::Fill>())
      out << ",\"fillRule\":" << object->as<rive::Fill>()->fillRule();
    out << '}';
  }
  RecordingRenderer renderer(factory);
  renderer.save();
  renderer.align(rive::Fit::contain, rive::Alignment::center,
                 rive::AABB(0, 0, kWidth, kHeight), artboard->bounds());
  artboard->draw(&renderer);
  renderer.restore();
  out << "],\"drawStackBalanced\":" << (renderer.balanced() ? "true" : "false")
      << ",\"drawCommands\":";
  writeDrawCommands(out, renderer.commands);
  out << '}';
}

Roi findRoi(const std::vector<uint8_t> &pixels) {
  Roi result;
  for (int y = 0; y < kHeight; ++y)
    for (int x = 0; x < kWidth; ++x) {
      const size_t offset = static_cast<size_t>((y * kWidth + x) * 4);
      if (pixels[offset] == kBackground[0] &&
          pixels[offset + 1] == kBackground[1] &&
          pixels[offset + 2] == kBackground[2] &&
          pixels[offset + 3] == kBackground[3])
        continue;
      result.left = std::min(result.left, x);
      result.top = std::min(result.top, y);
      result.right = std::max(result.right, x);
      result.bottom = std::max(result.bottom, y);
      ++result.foregroundPixels;
    }
  return result;
}

size_t changedPixels(const Frame &a, const Frame &b) {
  size_t count = 0;
  for (size_t offset = 0; offset + 3 < a.pixels.size(); offset += 4)
    if (!std::equal(a.pixels.begin() + offset, a.pixels.begin() + offset + 4,
                    b.pixels.begin() + offset))
      ++count;
  return count;
}

bool writePng(const std::string &path, const std::vector<uint8_t> &pixels) {
  auto space = CGColorSpaceCreateDeviceRGB();
  const auto info = static_cast<uint32_t>(kCGBitmapByteOrder32Big) |
                    static_cast<uint32_t>(kCGImageAlphaPremultipliedLast);
  auto provider = CGDataProviderCreateWithData(nullptr, pixels.data(),
                                               pixels.size(), nullptr);
  auto image =
      CGImageCreate(kWidth, kHeight, 8, 32, kWidth * 4, space, info, provider,
                    nullptr, false, kCGRenderingIntentDefault);
  auto url = CFURLCreateFromFileSystemRepresentation(
      nullptr, reinterpret_cast<const UInt8 *>(path.c_str()), path.size(),
      false);
  auto destination =
      CGImageDestinationCreateWithURL(url, CFSTR("public.png"), 1, nullptr);
  bool ok = false;
  if (destination && image) {
    CGImageDestinationAddImage(destination, image, nullptr);
    ok = CGImageDestinationFinalize(destination);
  }
  if (destination)
    CFRelease(destination);
  if (url)
    CFRelease(url);
  if (image)
    CGImageRelease(image);
  if (provider)
    CGDataProviderRelease(provider);
  if (space)
    CGColorSpaceRelease(space);
  return ok;
}

bool writeBytes(const std::string &path, const std::vector<uint8_t> &bytes) {
  std::ofstream output(path, std::ios::binary);
  return output &&
         (bytes.empty() || static_cast<bool>(output.write(
                               reinterpret_cast<const char *>(bytes.data()),
                               static_cast<std::streamsize>(bytes.size()))));
}

Frame captureRepresentative(rive::File *file, const OracleFactory &factory,
                            const std::string &referenceDir) {
  auto artboard = file->artboardAt(0);
  auto scene = artboard->animationAt(0);
  settleScene(scene.get(), 0, true);
  RecordingRenderer recording(factory);
  recording.save();
  recording.align(rive::Fit::contain, rive::Alignment::center,
                  rive::AABB(0, 0, kWidth, kHeight), artboard->bounds());
  artboard->draw(&recording);
  recording.restore();
  const auto command =
      std::find_if(recording.commands.begin(), recording.commands.end(),
                   [](const DrawCommand &candidate) {
                     return candidate.kind == "imageMesh";
                   });
  if (command == recording.commands.end() || !command->image ||
      !command->vertexBuffer || !command->uvBuffer || !command->indexBuffer) {
    std::cerr << "representative capture: image mesh not found\n";
    std::exit(10);
  }

  Frame frame;
  frame.filename = "representative-image-mesh.png";
  frame.pixels.resize(static_cast<size_t>(kWidth * kHeight * 4));
  for (size_t offset = 0; offset < frame.pixels.size(); offset += 4)
    std::copy(kBackground, kBackground + 4, frame.pixels.begin() + offset);
  auto space = CGColorSpaceCreateDeviceRGB();
  const auto info = static_cast<uint32_t>(kCGBitmapByteOrder32Big) |
                    static_cast<uint32_t>(kCGImageAlphaPremultipliedLast);
  auto context = CGBitmapContextCreate(frame.pixels.data(), kWidth, kHeight, 8,
                                       kWidth * 4, space, info);
  if (!context) {
    std::cerr << "representative capture: failed to create bitmap context\n";
    std::exit(10);
  }
  {
    rive::CGRenderer renderer(context, kWidth, kHeight);
    renderer.save();
    renderer.transform(command->transform);
    renderer.drawImageMesh(
        command->image, command->imageSampler, command->vertexBuffer,
        command->uvBuffer, command->indexBuffer, command->vertices.size(),
        command->indices.size(), command->blend, command->opacity);
    renderer.restore();
  }
  CGContextFlush(context);
  CGContextRelease(context);
  CGColorSpaceRelease(space);
  frame.roi = findRoi(frame.pixels);
  const std::string path = referenceDir + "/" + frame.filename;
  if (!writePng(path, frame.pixels)) {
    std::cerr << "representative capture: failed to write PNG\n";
    std::exit(10);
  }
  frame.sha = sha256File(path);
  return frame;
}

Frame capture(rive::File *file, size_t animationIndex, double seconds,
              bool bounded, const std::string &filename,
              const std::string &referenceDir) {
  auto artboard = file->artboardAt(0);
  auto scene = artboard->animationAt(animationIndex);
  settleScene(scene.get(), seconds, bounded);
  Frame frame;
  frame.filename = filename;
  frame.pixels.resize(static_cast<size_t>(kWidth * kHeight * 4));
  for (size_t offset = 0; offset < frame.pixels.size(); offset += 4)
    std::copy(kBackground, kBackground + 4, frame.pixels.begin() + offset);
  auto space = CGColorSpaceCreateDeviceRGB();
  const auto info = static_cast<uint32_t>(kCGBitmapByteOrder32Big) |
                    static_cast<uint32_t>(kCGImageAlphaPremultipliedLast);
  auto context = CGBitmapContextCreate(frame.pixels.data(), kWidth, kHeight, 8,
                                       kWidth * 4, space, info);
  if (!context) {
    std::cerr << "capture: failed to create bitmap context\n";
    std::exit(10);
  }
  {
    rive::CGRenderer renderer(context, kWidth, kHeight);
    renderer.save();
    renderer.align(rive::Fit::contain, rive::Alignment::center,
                   rive::AABB(0, 0, kWidth, kHeight), artboard->bounds());
    artboard->draw(&renderer);
    renderer.restore();
  }
  CGContextFlush(context);
  CGContextRelease(context);
  CGColorSpaceRelease(space);
  frame.roi = findRoi(frame.pixels);
  const std::string path = referenceDir + "/" + filename;
  if (!writePng(path, frame.pixels)) {
    std::cerr << "capture: failed to write PNG\n";
    std::exit(10);
  }
  frame.sha = sha256File(path);
  return frame;
}

std::string frameName(size_t animationIndex, double seconds, const char *mode) {
  std::ostringstream out;
  out << "timeline-" << animationIndex + 1 << '-' << mode << '-' << std::setw(6)
      << std::setfill('0') << std::lround(seconds * 1000) << "ms.png";
  return out.str();
}
} // namespace

int main(int argc, const char *argv[]) {
  Options options;
  if (!parseOptions(argc, argv, &options)) {
    std::cerr << "usage: rive_oracle_probe --asset FILE --output FILE "
                 "--reference-dir DIR --runtime-sha SHA\n";
    return 2;
  }
  std::vector<uint8_t> bytes;
  if (!readBytes(options.asset, &bytes))
    return 3;
  OracleFactory factory;
  rive::ImportResult importResult;
  auto file = rive::File::import(bytes, &factory, &importResult);
  if (!file) {
    std::cerr << "official runtime import failed: "
              << static_cast<int>(importResult) << '\n';
    return 4;
  }
  auto *definition = file->artboard(0);
  if (!definition || definition->animationCount() != 3)
    return 5;
  const double targets[] = {2.0,
                            definition->animation(1)->durationSeconds() / 2.0,
                            definition->animation(2)->durationSeconds() / 2.0};
  for (size_t index = 0; index < factory.images.size(); ++index) {
    std::ostringstream filename;
    filename << options.referenceDir << "/embedded-image-" << std::setw(2)
             << std::setfill('0') << index << ".png";
    if (!writeBytes(filename.str(), factory.images[index].encoded)) {
      std::cerr << "embedded image: failed to write payload\n";
      return 6;
    }
  }
  const auto representative =
      captureRepresentative(file.get(), factory, options.referenceDir);

  std::ofstream out(options.output);
  if (!out)
    return 6;
  out << std::setprecision(9);
  out << "{\n  \"schemaVersion\": 1,\n  \"assetSha256\": \"" << sha256(bytes)
      << "\",\n  \"officialRuntimeSha\": \"" << jsonEscape(options.runtimeSha)
      << "\",\n  \"tolerance\": "
      << "{\"absolute\":0.0001,\"relative\":0.00001},\n";
  out << "  \"images\": [";
  for (size_t index = 0; index < factory.images.size(); ++index) {
    if (index)
      out << ',';
    const auto &image = factory.images[index];
    out << "{\"index\":" << index << ",\"encodedBytes\":" << image.encodedBytes
        << ",\"encodedSha256\":\"" << image.encodedSha
        << "\",\"encodedFilename\":\"embedded-image-" << std::setw(2)
        << std::setfill('0') << index << ".png"
        << "\",\"width\":" << image.width << ",\"height\":" << image.height
        << '}';
  }
  out << "],\n  \"representativeSnapshot\":{\"animationIndex\":0,"
         "\"stateSeconds\":0,\"drawCommandIndex\":1,\"filename\":\""
      << representative.filename << "\",\"sha256\":\"" << representative.sha
      << "\",\"foregroundPixels\":" << representative.roi.foregroundPixels
      << ",\"roi\":{\"left\":" << representative.roi.left
      << ",\"top\":" << representative.roi.top
      << ",\"right\":" << representative.roi.right
      << ",\"bottom\":" << representative.roi.bottom
      << "}},\n  \"animations\": [\n";
  for (size_t animationIndex = 0; animationIndex < 3; ++animationIndex) {
    if (animationIndex)
      out << ",\n";
    auto *animation = definition->animation(animationIndex);
    out << "    {\"index\":" << animationIndex << ",\"name\":\""
        << jsonEscape(animation->name())
        << "\",\"targetSeconds\":" << targets[animationIndex]
        << ",\"states\":[";
    writeState(out, file.get(), factory, animationIndex, 0, true);
    out << ',';
    writeState(out, file.get(), factory, animationIndex,
               targets[animationIndex], true);
    out << ',';
    writeState(out, file.get(), factory, animationIndex,
               targets[animationIndex], false);

    const auto start =
        capture(file.get(), animationIndex, 0, true,
                frameName(animationIndex, 0, "bounded"), options.referenceDir);
    const auto bounded =
        capture(file.get(), animationIndex, targets[animationIndex], true,
                frameName(animationIndex, targets[animationIndex], "bounded"),
                options.referenceDir);
    const auto direct =
        capture(file.get(), animationIndex, targets[animationIndex], false,
                frameName(animationIndex, targets[animationIndex], "direct"),
                options.referenceDir);
    out << "],\"referenceFrames\":[";
    const Frame frames[] = {start, bounded, direct};
    for (size_t index = 0; index < 3; ++index) {
      if (index)
        out << ',';
      const auto &frame = frames[index];
      out << "{\"filename\":\"" << frame.filename << "\",\"sha256\":\""
          << frame.sha
          << "\",\"foregroundPixels\":" << frame.roi.foregroundPixels
          << ",\"roi\":{\"left\":" << frame.roi.left
          << ",\"top\":" << frame.roi.top << ",\"right\":" << frame.roi.right
          << ",\"bottom\":" << frame.roi.bottom << "}}";
    }
    out << "],\"changedPixels\":{\"bounded\":" << changedPixels(start, bounded)
        << ",\"direct\":" << changedPixels(start, direct)
        << ",\"boundedVsDirect\":" << changedPixels(bounded, direct) << "}}";
  }
  out << "\n  ]\n}\n";
  return out ? 0 : 7;
}
