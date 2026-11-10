#pragma once

#include <string>
#include <vector>

namespace fbv {

// One discipline key for an element, or "" when neither a system name nor the
// IFC class maps to a discipline. [system_texts] is name + description of each
// system the element belongs to, in ascending system id. The first text that
// maps wins, so a lower system id beats a later one. A system match beats the
// class table.
std::string assign_discipline(const std::string& ifc_class,
                              const std::vector<std::string>& system_texts);

}  // namespace fbv
