struct ProjectSymbol {
  int line;
};

#define SYMBOL_LIMIT 100

static const int PROJECT_LIMIT = 10;

auto MasterService::PutStart(int value) -> bool {
  return value > 0;
}

Result
WrappedMasterService::PutStart(int value) {
  return value;
}
