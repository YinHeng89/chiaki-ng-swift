#pragma once

#ifdef __cplusplus
#include <CoreFoundation/CoreFoundation.h>

#include <utility>

namespace video {

template <class Reference>
class Owned {
 public:
  Owned() noexcept = default;

  static auto adopting(Reference reference) noexcept -> Owned {
    Owned owned;
    owned.reference_ = reference;
    return owned;
  }

  static auto retaining(Reference reference) noexcept -> Owned {
    if (reference != nullptr) {
      CFRetain(reference);
    }
    return adopting(reference);
  }

  Owned(const Owned& other) noexcept : Owned(retaining(other.reference_)) {}

  Owned(Owned&& other) noexcept
      : reference_(std::exchange(other.reference_, nullptr)) {}

  auto operator=(Owned other) noexcept -> Owned& {
    std::swap(reference_, other.reference_);
    return *this;
  }

  ~Owned() {
    if (reference_ != nullptr) {
      CFRelease(reference_);
    }
  }

  auto get() const noexcept -> Reference { return reference_; }

  auto out() noexcept -> Reference* {
    *this = Owned{};
    return &reference_;
  }

  explicit operator bool() const noexcept { return reference_ != nullptr; }

 private:
  Reference reference_{};
};

}  // namespace video

#endif
