class Repository {
 public:
  virtual ~Repository() = default;
  virtual void save() = 0;
};

class SqlRepository : public Repository {
 public:
  void save() override {}
};

class CachedRepository : public SqlRepository {
 public:
  void save() override {}
};

class MemoryRepository : public Repository {
 public:
  void save() override {}
};
