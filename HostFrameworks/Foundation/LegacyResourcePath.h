#ifndef LC32_LEGACY_RESOURCE_PATH_H
#define LC32_LEGACY_RESOURCE_PATH_H

#include <cstddef>
#include <cstdint>

// Returns the length for a native mirror of a guest constant. Guest bytes
// and metadata remain untouched, including intentional embedded NULs.
std::size_t LC32LegacyResourcePathConstantLength(
    std::uint32_t flags, const void *bytes, std::size_t length,
    const char *executablePath);

#endif
