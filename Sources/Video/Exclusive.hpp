#pragma once

#ifdef __cplusplus
#include <memory>
#include <semaphore>
#include <utility>

namespace video {

template <class Value>
class Exclusive {
 public:
  Exclusive() noexcept = default;

  explicit Exclusive(std::unique_ptr<Value> value)
      : released_(value ? std::make_unique<std::binary_semaphore>(0) : nullptr),
        value_(std::move(value)) {
    if (value_) {
      shared_ = std::shared_ptr<Value>(
          value_.get(),
          [released = released_.get()](Value*) { released->release(); });
    }
  }

  Exclusive(const Exclusive&) = delete;
  auto operator=(const Exclusive&) -> Exclusive& = delete;

  Exclusive(Exclusive&& other) noexcept
      : released_(std::move(other.released_)),
        value_(std::move(other.value_)),
        shared_(std::move(other.shared_)) {}

  auto operator=(Exclusive&& other) noexcept -> Exclusive& {
    if (this != &other) {
      reset();
      released_ = std::move(other.released_);
      value_ = std::move(other.value_);
      shared_ = std::move(other.shared_);
    }
    return *this;
  }

  ~Exclusive() { reset(); }

  auto share() const noexcept -> std::shared_ptr<Value> { return shared_; }

  auto get() const noexcept -> Value* { return value_.get(); }

  explicit operator bool() const noexcept { return value_ != nullptr; }

  void reset() noexcept {
    if (!value_) {
      return;
    }
    shared_.reset();
    released_->acquire();
    value_.reset();
    released_.reset();
  }

 private:
  std::unique_ptr<std::binary_semaphore> released_;
  std::unique_ptr<Value> value_;
  std::shared_ptr<Value> shared_;
};

}  // namespace video

#endif
