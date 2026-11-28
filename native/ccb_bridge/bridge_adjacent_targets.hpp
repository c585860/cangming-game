#pragma once

#include <algorithm>
#include <vector>

#include "coordinates.h"

namespace ccb_bridge {

// The prompt and snapshot capture both run on the CCB worker thread.
inline thread_local const std::vector<tripoint_bub_ms> *adjacent_targets = nullptr;

class AdjacentTargetScope {
    public:
        explicit AdjacentTargetScope( const std::vector<tripoint_bub_ms> &targets ) :
            previous_( adjacent_targets ) {
            adjacent_targets = &targets;
        }

        ~AdjacentTargetScope() {
            adjacent_targets = previous_;
        }

        AdjacentTargetScope( const AdjacentTargetScope & ) = delete;
        AdjacentTargetScope &operator=( const AdjacentTargetScope & ) = delete;

    private:
        const std::vector<tripoint_bub_ms> *previous_;
};

inline bool is_adjacent_target( const tripoint_bub_ms &p ) {
    return adjacent_targets != nullptr &&
           std::find( adjacent_targets->begin(), adjacent_targets->end(), p ) != adjacent_targets->end();
}

} // namespace ccb_bridge
