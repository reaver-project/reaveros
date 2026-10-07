#include "header.h"
extern "C" int provided();
extern "C" int consumer() { return provided() + HEADER_VALUE; }
