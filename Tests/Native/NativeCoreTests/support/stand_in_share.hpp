#pragma once

#include <memory>

#include "share_desk.hpp"
#include "stream_session.hpp"

namespace chiaki_bridge {

class StandInShare {
 public:
  static void use(StreamSession& stream, libchiaking::kakusan::Kakusan& root) {
    stream.share_desk().roots_ = [&root]() {
      return std::shared_ptr<ShareDesk::Root>{std::shared_ptr<void>{}, &root};
    };
  }
};

}  // namespace chiaki_bridge
