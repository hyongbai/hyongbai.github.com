---
layout: post
title: "Redex源码分析2-Dex解析"
description: "Redex源码分析2-Dex解析"
category: all-about-tech
tags: -[redex，dex, android]
date: 2020-05-12 23:03:57+00:00
---

## Dex文件格式

Dex文件的魔数为根据不同版本与多个, 主要是一下几种:

- dex\n035\0
- dex\n036\0
- dex\n037\0
- dex\n038\0

并且是向下兼容的, API13及以下则使用的是`dex\n035\0`。

而`odex`文件也有自己的魔数, 为`dey\n036\0`。

[![aosp-dex-file-format-hd.png](https://j.mp/3fWVluZ)](https://j.mp/2X30Uzj)

> 图中左侧, class_defs也应该在idx区域。

### # DexHeader

```cpp
// dalvik/libdex/DexFile.h
struct DexHeader {
    u1  magic[8];           /* 魔数, dex\n开头, 同时也记录了dex的版本 */
    u4  checksum;           /* checksume */
    u1  signature[kSHA1DigestLen]; /* SHA-1签名, 为20个字节 */
    u4  fileSize;           /* dex文件的总大小 */
    u4  headerSize;         /* header区域的大小 */
    u4  endianTag;          /* 字节序, 固定为78563412, 即小端字节序。*/
    u4  linkSize;           /* 均是0 */
    u4  linkOff;            /* 均是0 */
    u4  mapOff;             /* MapItem的偏移地址 */
    u4  stringIdsSize;      /* String索引的数量 */
    u4  stringIdsOff;       /* String的偏移地址 */
    u4  typeIdsSize;        /* type(即类型)索引的数量 */
    u4  typeIdsOff;         /* type索引的偏移地址 */
    u4  protoIdsSize;       /* proto(包含了返回的typeID以及参数type列表)的数量 */
    u4  protoIdsOff;        /* proto的偏移地址 */
    u4  fieldIdsSize;       /* field索引的数量 */
    u4  fieldIdsOff;        /* field的偏移地址 */
    u4  methodIdsSize;      /* method索引的数量 */
    u4  methodIdsOff;       /* method的偏移地址 */
    u4  classDefsSize;      /* class声明的数量 */
    u4  classDefsOff;       /* class声明的偏移地址 */
    u4  dataSize;           /* data区域的总大小。fileSize?dataSize+headerSize */
    u4  dataOff;            /* data区域的偏移地址 */
};
```

`dex035`版本的dex文件对应的header固定长度为112个(即0x70)字节。

其中`xxxDdsSize/Off`对应的是对应类型的Id数量及其在data区域的偏移位置。除stringIds外, 其他id对应的字符串最终都引用的stringIds的索引。

注意, dex使用的是小端字节码。

比如file_size如果在dex中的数据为“28020000”, 那么实际表示的大小为“00000228”。也就是说dex中的, `0x12345678`实际对应的值是`0x78563412`, 即小端表示的是小的字节在前, 倒着度读即可。

### # DexStringId

```cpp
// dalvik/libdex/DexFile.h
struct DexStringId {
    u4 stringDataOff;      /* 记录的是对应字符串在data区域的偏移地址 */
};
```

也就是说想获取其最终值, 都需要经历如下步骤:

- 通过引用的stringIds+stringIdsOff拿到对应索引的字符在data中的偏移地址。

- 通过string的偏移地址在data区域读取真正的数值。

dex文件中所有的字符都以string索引的形式存在。 不论是函数名、成员名、类名等待都以string索引的形式引用。这样的好处就是, 字符串可以复用, 从而增加读取效率同时降低包体积。

### # DexFieldId

```cpp
// dalvik/libdex/DexFile.h
struct DexFieldId {
    u2  classIdx;           /* 所属的类, type索引(DexTypeId) */
    u2  typeIdx;            /* 变量类型, type索引(DexTypeId) */
    u4  nameIdx;            /* 变量名, string索引(DexStringId) */
};

struct DexTypeId {
    u4  descriptorIdx;      /* string索引(DexStringId) */
};
```

### # DexMethodId

```cpp
// dalvik/libdex/DexFile.h
struct DexMethodId {
    u2  classIdx;           /* type索引(DexTypeId) */
    u2  protoIdx;           /* proto索引 */
    u4  nameIdx;            /* string索引(DexStringId) */
};

struct DexProtoId {
    u4  shortyIdx;          /* string索引 */
    u4  returnTypeIdx;      /* 返回类型, type索引(DexTypeId) */
    u4  parametersOff;      /* DexTypeList的偏移地址 */
};

struct DexTypeList {
    u4  size;               /* list长度 */
    DexTypeItem list[1];    /* typeItem列表 */
};

struct DexTypeItem {
    u2  typeIdx;            /* type索引(DexTypeId) */
};
```

DexMethodId包含了8个字节, 其中2个字节长的classIdx(用于表示当前函数对应的Class), 和2个字节长的protoIdx(返回值和参数), 以及4个字节长的nameIdx(stringIds)。

从这里就可以看到dex文件为何有`65536`个类的限制了。解释一下, classIdx只被分配了2个字节长度( 也就是16位), 因此classIdx天然的最大值就只能是`65535`了。所以总和是无法超过`65536`的。

这里有点不一样的地方在于: `DexTypeList`并不存在索引, 在proto中存储的`parametersOff`直接就是它在文件中的偏移地址。

> 原则上来说`DexTypeList`也可以以索引的方式存储在dex文件中, DexProtoId记录其索引即可。毕竟函数的参数列表存在复用的可能性是非常大的。


### # DexClassDef

```cpp
// dalvik/libdex/DexFile.h
struct DexClassDef {
    u4  classIdx;           /* 当前类, type索引(DexTypeId) */
    u4  accessFlags;        /* 访问标志位 */
    u4  superclassIdx;      /* 父类, type索引(DexTypeId) */
    u4  interfacesOff;      /* 实现的接口, 为DexTypeList的偏移地址 */
    u4  sourceFileIdx;      /* 源文件名, string索引(DexStringId) */
    u4  annotationsOff;     /* 类注解, 为DexAnnotationsDirectoryItem的偏移地址 */
    u4  classDataOff;       /* 对应的DexClassData在文件中的偏移地址 */
    u4  staticValuesOff;    /* file offset to DexEncodedArray */
};
```

类的定义中有8个字段, 每个字段4个字节, 共32个字节。

这里面包括类对应的Type索引, 访问操作符, 父类的type索引、实现的接口对应的DexTypeList以及注解和DexClassData。

其中`interfacesOff`、`annotationsOff`、`classDataOff`、`staticValuesOff`记录的都是在文件中的偏移地址, 而非对应的索引, dex035中并没有这种操作。

DexClassData则包含了类中所有的成员以及方法等。

### # DexClassData

DexClassData中包含了成员和方法的集合。并且区分了静态和非静态两种, 也就是说这里包含了4个集合。

但是, 仅仅有这些容器是无法对数据进行解析的。因此还需要另外的字段用以解析这些数据, 这个数据结构就是`DexClassDataHeader`。如下:


```cpp
// dalvik/libdex/DexClass.h
struct DexClassDataHeader {
    u4 staticFieldsSize;
    u4 instanceFieldsSize;
    u4 directMethodsSize;
    u4 virtualMethodsSize;
};
```

可以看到这里这里有着4个size, 分别表示ClassData对应的4个集合。由于Dex都是结构化数据, 因此只要按照`staticFields`、`instanceFields`、`directMethods`、`virtualMethods`这个顺序根据其size一一解析即可。

下面是`DexClassData`的数据类型:

```cpp
// dalvik/libdex/DexClass.h
struct DexClassData {
    DexClassDataHeader header;
    DexField*          staticFields;
    DexField*          instanceFields;
    DexMethod*         directMethods;
    DexMethod*         virtualMethods;
};

/* expanded form of encoded_field */
struct DexField {
    u4 fieldIdx;    /* 对应的field索引(DexFieldId) */
    u4 accessFlags; /* 访问标志位 */
};

/* expanded form of encoded_method */
struct DexMethod {
    u4 methodIdx;    /* 对应的函数索引(DexMethodId) */
    u4 accessFlags;  /* 访问标志位 */
    u4 codeOff;      /* 方法体的偏移地址 */
};
```

在这里, 对于Field和Method的引用是`DexField`和`DexMethod`这两个新的数据结构, 而不是header中定义的`DexFieldIdx`和`DexMethodIdx`。以`DexMethod`为例:

这里面有`methodIdx`、`accessFlags`以及`codeOff`, 它描述的是当前class中这个Method的描述数据。包含了函数签名、访问标志位、以及最重要的方法体DexCode(这里并未列出)。

下面这张图描绘了, Header和Data中各个结构体的相互关系, 如下:

[![aosp-dex-file-field-method-class.png](https://j.mp/2X55du4)](https://j.mp/2Ze589Y)

> 上图的DexField有误, filedIdx正确对应的应该是DexFieldId

### # Dex文件格式总结

简单来说Dex文件分为了两个区域: Header和Data。但是如果你把dataSize和headerSize相加, 一定是比fileSize要小的。因为在Header和Data中间还有一段数据, 存储的是Header中5种idx对应的偏移地址。因此Dex分为Header/Idx/Data三个区域。

~~Dex文件为了减少class文件的大小, 使用了索引来替代对String/Type/Field/Proto/Method的引用, 在不全部解析出数据的情况下, 只要通过idx就可以查找到对应的资源。~~

- [>>> dalvik/libdex/DexFile.h文件源码](https://j.mp/2yKUHjD)
- [>>> dalvik/libdex/DexClass.h文件源码](https://j.mp/2Lqjegq)

## Redex解析Dex

### # redex_frontend

```cpp
// redex/tools/redex-all/main.cpp
void redex_frontend(ConfigFiles& conf, /* input */
                    Arguments& args, /* inout */
                    keep_rules::ProguardConfiguration& pg_config,
                    DexStoresVector& stores,
                    Json::Value& stats) {
  ...
  // 创建一个用于存储所有class的DexStore实例
  DexStore root_store("classes");
  // 解析dex文件header的magic数, 并设置到root_store中
  // magic为8个字节长, 值为"dex\n035\0"或者"dex\n037\0"
  root_store.set_dex_magic(get_dex_magic(args.dex_files));
  // 添加到stores向量
  stores.emplace_back(std::move(root_store));

  // conf就是redex运行时指定的config文件, 这里将其读取json对象
  const JsonWrapper& json_config = conf.get_json_config();
  dup_classes::read_dup_class_whitelist(json_config);

  { // 解析dex文件列表
    dex_stats_t input_totals;
    // 每个dex文件都对应一个的redex-stats.txt
    std::vector<dex_stats_t> input_dexes_stats;
    for (const auto& filename : args.dex_files) {
      // 文件必须有效, 判断方式为: 文件名大于4同时必须以dex为后缀
      if (filename.size() >= 5 &&
          filename.compare(filename.size() - 4, 4, ".dex") == 0) {
        // 校验每个文件的magic是否与上面设置的一致。
        assert_dex_magic_consistency(stores[0].get_dex_magic(),
                                     load_dex_magic_from_dex(filename.c_str()));
        dex_stats_t dex_stats;
        // 使用DexLoader从dex文件中解析出class
        DexClasses classes =
            load_classes_from_dex(filename.c_str(), &dex_stats);
        input_totals += dex_stats;
        input_dexes_stats.push_back(dex_stats);
        // 来自参数的dex文件添加到第一个DexStore对象中, 即上面的root_store。
        stores[0].add_classes(std::move(classes));
      } else {
        // 如果不是dex文件, 那么将其解析为DexMetadata
        DexMetadata store_metadata;
        store_metadata.parse(filename);
        DexStore store(store_metadata);
        // 解析metadata中的dex文件列表, for循环中处理dex的逻辑与上面一致
        for (const auto& file_path : store_metadata.get_files()) {
          assert_dex_magic_consistency(
              stores[0].get_dex_magic(),
              load_dex_magic_from_dex(file_path.c_str()));
          dex_stats_t dex_stats;
          DexClasses classes =
              load_classes_from_dex(file_path.c_str(), &dex_stats);

          input_totals += dex_stats;
          input_dexes_stats.push_back(dex_stats);
          store.add_classes(std::move(classes));
        }
        // 每一个metadata都单独对应一个DexStore
        stores.emplace_back(std::move(store));
      }
    }
    stats["input_stats"] = get_input_stats(input_totals, input_dexes_stats);
  }
  ...
}
```

DexStoresVector是一个存储DexStore的向量, DexStore则中持有的m_dexen是存储了DexClasses的向量。而DexClasses则是保存单个dex文件中所有的DexClass的向量。

相互关系如下图:

[![redex-DexStoresVector-2-DexClass.png](https://j.mp/35RBdFS)](https://j.mp/2yQ5J6V)

### # load_classes_from_dex

```cpp
// redex/libredex/DexLoader.cpp
DexClasses load_classes_from_dex(const char* location,
                                 dex_stats_t* stats,
                                 bool balloon = true,
                                 bool support_dex_v37 = false);
DexClasses load_classes_from_dex() {
  DexLoader dl(location);
  // 加载指定路径dex文件, 这里返回的是DexClasses实例
  auto classes = dl.load_dex(location, stats, support_dex_v37);
  if (balloon) {
    balloon_all(classes);
  }
  return classes;
}
```

这一步是创建DexCloader的实例, 并调用其load_dex函数, 返回DexClasses结构体。

下面继续来看, Dex是如何解析的。

## Dex文件的解析

```cpp
// redex/libredex/DexLoader.cpp
DexClasses DexLoader::load_dex(const char* location,
                               dex_stats_t* stats,
                               bool support_dex_v37) {
  // 加载dex的header,
  const dex_header* dh = get_dex_header(location);
  // 校验header:
  // 比如是否支持dex037;
  // 文件大小是否同头文件存储的文件大小一致;
  // class_defs_off以及class_defs_size是否越过dex_size(file_size)等
  validate_dex_header(dh, m_file.size(), support_dex_v37);
  // 加载dex中的类集合
  return load_dex(dh, stats);
}
```

这里先解析dex文件的header并校验, 校验通过则解析`Dex_Class_Def`。否则中断程序运行。

### # 解析header

上面介绍dex可知, 在035版本中, header区域的大小为112(即0x70)个字节。对于结构化的数据, 在cpp层解析还是挺方便的。

```cpp
// redex/libredex/DexLoader.cpp
const dex_header* DexLoader::get_dex_header(const char* location) {
  m_file.open(location, boost::iostreams::mapped_file::readonly);
  if (!m_file.is_open()) {
    fprintf(stderr, "error: cannot create memory-mapped file: %s\n", location);
    exit(EXIT_FAILURE);
  }
  // 强转为dex_header对象
  return reinterpret_cast<const dex_header*>(m_file.const_data());
}
```

dex_header结构体如下:

```cpp
// redex/shared/DexDefs.cpp
PACKED(struct dex_header {
  char magic[8];
  uint32_t checksum;
  uint8_t signature[20];
  uint32_t file_size;
  uint32_t header_size;
  uint32_t endian_tag;
  uint32_t link_size;
  uint32_t link_off;
  uint32_t map_off;
  uint32_t string_ids_size;
  uint32_t string_ids_off;
  uint32_t type_ids_size;
  uint32_t type_ids_off;
  uint32_t proto_ids_size;
  uint32_t proto_ids_off;
  uint32_t field_ids_size;
  uint32_t field_ids_off;
  uint32_t method_ids_size;
  uint32_t method_ids_off;
  uint32_t class_defs_size;
  uint32_t class_defs_off;
  uint32_t data_size;
  uint32_t data_off;
});
```

这里同android源码对dex的描述完全一致, 见上面。

继续来看redex是如何校验header的:

```cpp
// redex/libredex/DexLoader.cpp
#define DEX_HEADER_DEXMAGIC_V35 "dex\n035"
#define DEX_HEADER_DEXMAGIC_V37 "dex\n037"
static void validate_dex_header(const dex_header* dh,
                                size_t dexsize,
                                bool support_dex_v37) {
  if (support_dex_v37) {
    // 字符串比较: 不等于dex_v37或者dex_v25都会assert中断运行
    if (memcmp(dh->magic, DEX_HEADER_DEXMAGIC_V37, sizeof(dh->magic)) &&
        memcmp(dh->magic, DEX_HEADER_DEXMAGIC_V35, sizeof(dh->magic))) {
      always_assert_log(false, "Bad v35 or v37 dex magic %s\n", dh->magic);
    }
  } else {
    // 如果未开启dex_v37, 则要求magic必须等于V35
    if (memcmp(dh->magic, DEX_HEADER_DEXMAGIC_V35, sizeof(dh->magic))) {
      always_assert_log(false, "Bad v35 dex magic %s\n", dh->magic);
    }
  }
  // 校验header中的file_size是否同dexSize一致
  always_assert_log(
      dh->file_size == dexsize,
      "Reported size in header (%z) does not match file size (%u)\n",
      dexsize,
      dh->file_size);
  // 获取data区域的偏移地址
  auto off = (uint64_t)dh->class_defs_off;
  // 计算header中定义的所有的Class_def对应总空间大小。
  // 根据上面介绍dex可知, dex_class_def应当是32个字节。
  auto limit = off + dh->class_defs_size * sizeof(dex_class_def);
  // data区域的偏移地址必须小于dex文件大小。
  always_assert_log(off < dexsize, "class_defs_off out of range");
  // class_def的大小不能超过dex文件大小。
  always_assert_log(limit <= dexsize, "invalid class_defs_size");
}
```

把上面校验header的条件列出:

- 校验魔数。

根据是否开启dex_037(默认不开启)稍微不同。

如果魔数不为dex\n035, 同时开启037且不等于dex\n037则校验不通过。

- 校验文件大小。

比较header的file_size字段(即0x20到0x23这四个字节数)的值是否等于文件大小。

- 校验数据是否越界。

data区域的大小和偏移是header的倒数8个字节。一个有效的dex文本的data区域大小和偏移地址一定是小于dex文件大小本身的。

- 校验class_def是否越界。

由于class_def也是结构化的数据, 其大小为32个字节。很容易通过class_def_size计算出所有class_def的大小。这个值是不能超过dex_size的。个人感觉这个校验不是很有意义。

其实还有很多点可以校验, 比如:

- dataSize+dataOffset应该等于dexSize。

- dataOffset一定大于header_size + (idx的总大小)。

- map_off是否大于data_off。

- Checksum以及signature。

### # 解析class

到这一步就是对Class_def的解析了。header中提到的String/Field/Method等等也都是在这一步解析出来的。

dex文件的解析主要是分为两个部分: idx的解析和Class_Def的解析。

如下:

```cpp
// libredex/DexLoader.cpp
DexClasses DexLoader::load_dex(const dex_header* dh, dex_stats_t* stats) {
  if (dh->class_defs_size == 0) {
    return DexClasses(0);
  }
  // 将header中id相关的字段解析出来。
  // redex封装了DexIdx专门用于处理header定义的idx。
  // 包括: string/type/field/method/proto对应的ids_off和ids_size
  m_idx = new DexIdx(dh);
  // 获取dex文件头中class的位移

  auto off = (uint64_t)dh->class_defs_off;
  // 读取首个class, 用作base
  m_class_defs =
      reinterpret_cast<const dex_class_def*>((const uint8_t*)dh + off);
  // 创建DexClasses, 这是一个DexClass的向量。
  // header的class_defs_size字段表示当前dex中包含的class数量。
  DexClasses classes(dh->class_defs_size);
  m_classes = &classes;

  // 创建结构体class_load_work集合
  auto lwork = new class_load_work[dh->class_defs_size];
  // 创建WorkQueue, 用于并行解析dex中的class
  // 其中mapper为class_work, input为class_load_work。
  // 默认线程数为cpu核心数, 即redex_parallel::default_num_threads()。
  // 比如i78700对应的是6。
  auto wq =
      workqueue_mapreduce<class_load_work*, std::vector<std::exception_ptr>>(
          class_work, exc_reducer);
  // for循环, 填充lwork中的每一个class_load_work
  for (uint32_t i = 0; i < dh->class_defs_size; i++) {
    lwork[i].dl = this;
    lwork[i].num = i;
    wq.add_item(&lwork[i]);
  }
  // 并行运行wq队列中的任务
  const auto exceptions = wq.run_all();
  // 删除集合
  delete[] lwork;

  // 处理异常并抛出
  if (!exceptions.empty()) {
    aggregate_exception ae(exceptions);
    throw ae;
  }
  gather_input_stats(stats, dh);
  // 清除队列中为空的项
  classes.erase(std::remove(classes.begin(), classes.end(), nullptr),
                classes.end());
  return classes;
}
```

下面是work_queue的回调函数 `class_work` 的实现:

```cpp
// libredex/DexLoader.cpp
static std::vector<std::exception_ptr> class_work(class_load_work* clw) {
  // class_work是workqueue的回调函数
  try {
    // 加载第`clw->num`个class
    clw->dl->load_dex_class(clw->num);
    return {}; // no exception
  } catch (const std::exception& exc) {
    TRACE(MAIN, 1, "Worker throw the exception:%s", exc.what());
    return {std::current_exception()};
  }
}
void DexLoader::load_dex_class(int num) {
  // num表示第n个class_defs
  const dex_class_def* cdef = m_class_defs + num;
  // 生成对应的DexClass实例
  DexClass* dc = DexClass::create(m_idx, cdef, m_dex_location);
  m_classes->at(num) = dc;
}
```

这里是按照header定义的class_def_size遍历生成对应数量的DexClass文件, 并添加到`吗_classes`中。

下面看看DexClass是如何解析类的。

#### - DexClass

DexClass同DexClassDef结构体是两回事。

dex_class_def记录的是DexClass中相关字段的偏移地址或者相关索引而已。而DexClass则是将`dex_class_def`中的信息拿出来, 进一步解析成对应的值。

举例来说就是, dex_class_def的`source_file_idx`表示使用的String索引, 而DexClass的`m_source_file`则是通过前面的索引(`source_file_idx`)将其代表的具体的数值解析出来。

```cpp
// libredex/DexClass.cpp
DexClass* DexClass::create(DexIdx* idx,
                           const dex_class_def* cdef,
                           const std::string& location) {
  // 创建DexClass对象。
  DexClass* cls = new DexClass(idx, cdef, location);
  if (g_redex->class_already_loaded(cls)) {
    delete cls;
    return nullptr;
  }
  // 加载注解
  cls->load_class_annotations(idx, cdef->annotations_off);
  // 加载静态数值列表。用于读取静态成员的原始值。
  auto deva = std::unique_ptr<DexEncodedValueArray>(
      load_static_values(idx, cdef->static_values_off));
  // 加载class_data: 加载成员, 静态成员, 方法, 抽象方法等
  cls->load_class_data_item(idx, cdef->class_data_offset, deva.get());
  g_redex->publish_class(cls);
  return cls;
}

DexClass::DexClass(DexIdx* idx,
                   const dex_class_def* cdef,
                   const std::string& location)
    : // 访问标志位
      m_access_flags((DexAccessFlags)cdef->access_flags),
      // 父类的类型, 注意这里是typeidx, 可从DexIdx解析对应类型
      m_super_class(idx->get_typeidx(cdef->super_idx)),
      // 当前类的类型
      m_self(idx->get_typeidx(cdef->typeidx)),
      // 实现的接口列表
      m_interfaces(idx->get_type_list(cdef->interfaces_off)),
      // class的源文件
      m_source_file(idx->get_nullable_stringidx(cdef->source_file_idx)),
      // 注解
      m_anno(nullptr),
      m_external(false),
      m_perf_sensitive(false),
      // 记录dex文件位置
      m_location(location) {
}
```

下面就DexString、DexType、DexClass、DexField、DexMethod分析redex如何解析dex文件。

#### - 解析DexString/Type

- DexString

```cpp
// redex/libredex/DexIdx.h
DexString* get_stringidx(uint32_t stridx) {
// 从缓存读取
if (m_string_cache[stridx] == nullptr) {
  // 无缓存则从头解析
  m_string_cache[stridx] = get_stringidx_fromdex(stridx);
}
redex_assert(m_string_cache[stridx]);
return m_string_cache[stridx];
}

// redex/libredex/DexIdx.cpp
DexString* DexIdx::get_stringidx_fromdex(uint32_t stridx) {
  redex_assert(stridx < m_string_ids_size);
  // 从string_ids中拿到对应索引的偏移地址。
  // 偏移地址offset以及size都是在Dex的header中定义的。
  uint32_t stroff = m_string_ids[stridx].offset;
  always_assert_log(stroff < ((dex_header*)m_dexbase)->file_size,
                    "String data offset out of range");
  // 计算真实的内存地址, 即base加上偏移地址
  const uint8_t* dstr = m_dexbase + stroff;
  // 读取偏移地址中定义的当前字符串的长度
  // dex中对于单个字符串的size是通过变长类型uleb128来存储的。
  // 读取变长类型的时候, 当前的偏移地址会往后相应的移动。
  int utfsize = read_uleb128(&dstr);
  // 通过偏移地址以及字符串的长度, 很容易可以读出正确的字符串
  return DexString::make_string((const char*)dstr, utfsize);
}

```

读取字符串的过程可以理解为如下:

1> 通过字符串索引, 拿到对应字符串的偏移地址。

2> 通过偏移地址, 先读取字符串长度和字符串的实际字符。

- DexType

解析DexType的过程与String一样。

```cpp
// redex/libredex/DexIdx.h
DexType* get_typeidx(uint32_t typeidx) {
if (typeidx == DEX_NO_INDEX) {
  return nullptr;
}
// 读取缓存, 如无则开始解析
if (m_type_cache[typeidx] == nullptr) {
  m_type_cache[typeidx] = get_typeidx_fromdex(typeidx);
}
// 返回结果
return m_type_cache[typeidx];
}

// redex/libredex/DexIdx.cpp
DexType* DexIdx::get_typeidx_fromdex(uint32_t typeidx) {
  redex_assert(typeidx < m_type_ids_size);
  // 读取DexTypeId引用的string索引id
  // 通过分析dex文件的结构可知对于DexType, 只用了一个字符串表示其描述。
  uint32_t stridx = m_type_ids[typeidx].string_idx;
  // 通过string索引, 解析对应的字符串
  DexString* dexstr = get_stringidx(stridx);
  // 通过字符串创建DexType
  return DexType::make_type(dexstr);
}
```

uleb128为dex中特有的一个变长类型。

特点在于每个字节的最高位用于标记是否包含下一个字节, 最高位为1表示使用下一字节, 为0则不使用。因此, 一个32位的数, 只有28位有效位。

这也的好处在于, 比如127位以下的string, 只用一个字节即可, 降低了dex文件的大小。

#### - 解析ClassData

这一部分代码解析的是数据对应的是`dalvik/libdex/DexClass.h`里定义的`DexClassDataHeader`。

```cpp
// libredex/DexClass.cpp
void DexClass::load_class_data_item(DexIdx* idx,
                                    uint32_t cdi_off,
                                    DexEncodedValueArray* svalues) {
  if (cdi_off == 0) return;
  const uint8_t* encd = idx->get_uleb_data(cdi_off);
  // 解析ClassDataHeader
  // 解析出来4个size, 这同dex里面的描述一致
  uint32_t sfield_count = read_uleb128(&encd);
  uint32_t ifield_count = read_uleb128(&encd);
  uint32_t dmethod_count = read_uleb128(&encd);
  uint32_t vmethod_count = read_uleb128(&encd);
  uint32_t ndex = 0;
  // 解析静态成员
  for (uint32_t i = 0; i < sfield_count; i++) {
    // 读取对应的DexFieldId的索引
    ndex += read_uleb128(&encd);
    // 读取access_flags
    auto access_flags = (DexAccessFlags)read_uleb128(&encd);
    // 将索引值转化成对应的偏移地址, 并将偏移地址读成结构化的DexField对象
    DexField* df = static_cast<DexField*>(idx->get_fieldidx(ndex));
    DexEncodedValue* ev = nullptr;
    if (svalues != nullptr) {
      // 获取静态成员的值
      ev = svalues->pop_next();
    }
    // 具体化DexField, 即access_flags和默认值等。
    // 只有静态成员在这一步才会设定值, 否则设定为null。
    df->make_concrete(access_flags, ev);
    // 添加到集合
    m_sfields.push_back(df);
  }
  ndex = 0;
  // 解析普通成员, 同上面静态成员一致。
  for (uint32_t i = 0; i < ifield_count; i++) {
    ndex += read_uleb128(&encd);
    auto access_flags = (DexAccessFlags)read_uleb128(&encd);
    DexField* df = static_cast<DexField*>(idx->get_fieldidx(ndex));
    df->make_concrete(access_flags);
    m_ifields.push_back(df);
  }

  std::unordered_set<DexMethod*> method_pointer_cache;

  ndex = 0;
  // 解析普通方法
  for (uint32_t i = 0; i < dmethod_count; i++) {
    // 读取DexMethodId的索引
    ndex += read_uleb128(&encd);
    // 读取access_flags
    auto access_flags = (DexAccessFlags)read_uleb128(&encd);
    // 读取方法code的偏移地址
    uint32_t code_off = read_uleb128(&encd);
    // 通过索引去DexIdx中读取DexMethod对象。
    DexMethod* dm = static_cast<DexMethod*>(idx->get_methodidx(ndex));
    // 通过code偏移地址, 加载DexCode
    std::unique_ptr<DexCode> dc = DexCode::get_dex_code(idx, code_off);
    if (dc && dc->get_debug_item()) {
      // 绑定调试信息
      dc->get_debug_item()->bind_positions(dm, m_source_file);
    }
    // 具体化DexMethod对象。
    dm->make_concrete(access_flags, std::move(dc), false);
    ...
    method_pointer_cache.insert(dm);
    m_dmethods.push_back(dm);
  }
  ndex = 0;
  // 解析静态方法, 与普通方法无异
  for (uint32_t i = 0; i < vmethod_count; i++) {
    ndex += read_uleb128(&encd);
    auto access_flags = (DexAccessFlags)read_uleb128(&encd);
    uint32_t code_off = read_uleb128(&encd);
    // Find method in method index, returns same pointer for same method.
    DexMethod* dm = static_cast<DexMethod*>(idx->get_methodidx(ndex));
    auto dc = DexCode::get_dex_code(idx, code_off);
    if (dc && dc->get_debug_item()) {
      dc->get_debug_item()->bind_positions(dm, m_source_file);
    }
    // 这里最后一个参数为true, 表示静态类型。
    dm->make_concrete(access_flags, std::move(dc), true);
    ...
    method_pointer_cache.insert(dm);
    m_vmethods.push_back(dm);
  }
}
```

下面分别继续看DexField和DexMethod是如何解析的。

#### - 解析Field

```cpp
// redex/libredex/DexIdx.h
DexFieldRef* get_fieldidx(uint32_t fidx) {
// 检查缓存
if (m_field_cache[fidx] == nullptr) {
  // 如无缓存, 则创建新对象
  m_field_cache[fidx] = get_fieldidx_fromdex(fidx);
}
redex_assert(m_field_cache[fidx]);
return m_field_cache[fidx];
}
```

```cpp
// redex/libredex/DexIdx.cpp
DexFieldRef* DexIdx::get_fieldidx_fromdex(uint32_t fidx) {
  redex_assert(fidx < m_field_ids_size);
  // 从field_ids索引列表中分别读取目标idx的数据。
  // 这里的数据比如container、type、string也是各自类型对应的idx。
  // 需要继续在对应类型中获取相应的DexXXX对象
  DexType* container = get_typeidx(m_field_ids[fidx].classidx);
  DexType* ftype = get_typeidx(m_field_ids[fidx].typeidx);
  DexString* name = get_stringidx(m_field_ids[fidx].nameidx);
  // 创建DexField对象
  return DexField::make_field(container, name, ftype);
}
```

```cpp
// redex/libredex/DexClass.h
static DexFieldRef* make_field(const DexType* container,
                             const DexString* name,
                             const DexType* type) {
return g_redex->make_field(container, name, type);
}

// redex/libredex/RedexContext.cpp
DexFieldRef* RedexContext::make_field(const DexType* container,
                                      const DexString* name,
                                      const DexType* type) {
  always_assert(container != nullptr && name != nullptr && type != nullptr);
  DexFieldSpec r(const_cast<DexType*>(container),
                 const_cast<DexString*>(name),
                 const_cast<DexType*>(type));
  auto rv = s_field_map.get(r, nullptr);
  if (rv != nullptr) {
    return rv;
  }
  auto field = new DexField(const_cast<DexType*>(container),
                            const_cast<DexString*>(name),
                            const_cast<DexType*>(type));
  return try_insert<DexField, DexFieldRef>(r, field, &s_field_map);
}
```

```cpp
// redex/libredex/RedexContext.cpp
DexField* DexFieldRef::make_concrete(DexAccessFlags access_flags,
                                     DexEncodedValue* v) {
  // FIXME assert if already concrete
  auto that = static_cast<DexField*>(this);
  // 设定访问标志位
  that->m_access = access_flags;
  // 标记已具体化
  that->m_concrete = true;
  // 如果是静态成员, 则设定默认值。
  if (is_static(access_flags)) {
    that->set_value(v);
  } else {
    always_assert(v == nullptr);
  }
  return that;
}
```

#### - 解析Method

```cpp
// redex/libredex/DexIdx.h
DexMethodRef* get_methodidx(uint32_t midx) {
// 读取缓存
if (m_method_cache[midx] == nullptr) {
  // 从dex文件解析
  m_method_cache[midx] = get_methodidx_fromdex(midx);
}
redex_assert(m_method_cache[midx]);
return m_method_cache[midx];
}
```

```
// redex/libredex/DexIdx.cpp
DexMethodRef* DexIdx::get_methodidx_fromdex(uint32_t midx) {
  // 根据dex文件结果, 通过method索引, 读取DexMethodId相关信息
  // 读取对应的类的type, 同DexClassDef中对应的classidx一致。
  DexType* container = get_typeidx(m_method_ids[midx].classidx);
  // 读取对应的proto字段
  DexProto* proto = get_protoidx(m_method_ids[midx].protoidx);
  // 读取函数名, 即string
  DexString* name = get_stringidx(m_method_ids[midx].nameidx);
  return DexMethod::make_method(container, name, proto);
}
```

```cpp
// redex/libredex/DexClass.h
static DexMethodRef* make_method(DexType* type,
                               DexString* name,
                               DexProto* proto) {
return g_redex->make_method(type, name, proto);
}


// redex/libredex/RedexContext.cpp
DexMethodRef* RedexContext::make_method(const DexType* type_,
                                        const DexString* name_,
                                        const DexProto* proto_) {
  auto type = const_cast<DexType*>(type_);
  auto name = const_cast<DexString*>(name_);
  auto proto = const_cast<DexProto*>(proto_);
  // 创建缓存索引
  DexMethodSpec r(type, name, proto);
  // 读取缓存
  auto rv = s_method_map.get(r, nullptr);
  if (rv != nullptr) {
    return rv;
  }
  // 存入缓存
  return try_insert<DexMethod, DexMethodRef, DexMethod::Deleter>(
      r, new DexMethod(type, name, proto), &s_method_map);
}
```

上面的解析, 都是基于DexMethodId来展开的。也就是说, 前面解析的都是跟其签名有关。而真正的函数实现是在DexCode中完成的。同理, 上面解析field的时候也是一样。

最后都需要调用make_concrete, 将dexcode设置进来, 完成DexMethod的完整解析。

```cpp
// redex/libredex/DexClass.cpp
DexMethod* DexMethodRef::make_concrete(DexAccessFlags access,
                                       std::unique_ptr<DexCode> dc,
                                       bool is_virtual) {
  auto that = static_cast<DexMethod*>(this);
  that->m_access = access;
  that->m_dex_code = std::move(dc);
  that->m_concrete = true;
  that->m_virtual = is_virtual;
  return that;
}
```

不过, 在这里并没有DexCode的解析过程。还得回到上面解析DexClassData那里, 后面处理函数时调用`DexCode::get_dex_code`完成对DexCode的解析。

#### - 解析DexCode

DexCode(`dex_code_item`)同DexField以及DexMethod一样, 是Data区域的数据结构。

其数据结构为:

```cpp
// dalvik/libdex/DexClass.h
struct DexCode {
    u2  registersSize;
    u2  insSize;
    u2  outsSize;
    u2  triesSize;
    u4  debugInfoOff;       /* file offset to debug info stream */
    u4  insnsSize;          /* size of the insns array, in u2 units */
    u2  insns[1];
    /* followed by optional u2 padding */
    /* followed by try_item[triesSize] */
    /* followed by uleb128 handlersSize */
    /* followed by catch_handler_item[handlersSize] */
};

// redex/shared/DexDefs.h
PACKED(struct dex_code_item {
  uint16_t registers_size;
  uint16_t ins_size;
  uint16_t outs_size;
  uint16_t tries_size;
  uint32_t debug_info_off;
  uint32_t insns_size;
});
```

上面为android源码的定义, 而在redex中被定义为`dex_code_item`, 不过他们是完全一致的。

> dalvik里面有一个两字节的`insns`, 而redex中则没有。

`dex_code_item` 是记录的是相关的信息, 而 `DexCode` 则是将 `dex_code_item` 解析出来之后的类。

如下:

```cpp
// redex/libredex/DexClass.cpp
std::unique_ptr<DexCode> DexCode::get_dex_code(DexIdx* idx, uint32_t offset) {
  if (offset == 0) return std::unique_ptr<DexCode>();
  // 从偏移地址, 读出DexCodeItem。
  // 这里面包含了DexCode的一些数据。用于解析出DexCode
  const dex_code_item* code = (const dex_code_item*)idx->get_uint_data(offset);

  // 创建DexCode, 并将DexCodeItem中的属性传递过来。
  std::unique_ptr<DexCode> dc(new DexCode());
  dc->m_registers_size = code->registers_size;
  dc->m_ins_size = code->ins_size;
  dc->m_outs_size = code->outs_size;
  dc->m_insns.reset(new std::vector<DexInstruction*>());

  //
  const uint16_t* cdata = (const uint16_t*)(code + 1);
  uint32_t tries = code->tries_size;
  if (code->insns_size) {
    // 解析instruction
    const uint16_t* end = cdata + code->insns_size;
    while (cdata < end) {
      DexInstruction* dop = DexInstruction::make_instruction(idx, &cdata);
      dc->m_insns->push_back(dop);
    }
    /*
     * Padding, see dex-spec.
     * Per my memory, there are dex-files where the padding is
     * implemented not according to spec.  Just FYI in case
     * something weird happens in the future.
     */
    if (code->insns_size & 1 && tries) cdata++;
  }

  if (tries) {
    const dex_tries_item* dti = (const dex_tries_item*)cdata;
    const uint8_t* handlers = (const uint8_t*)(dti + tries);
    for (uint32_t i = 0; i < tries; i++) {
      DexTryItem* dextry = new DexTryItem(dti[i].start_addr, dti[i].insn_count);
      const uint8_t* handler = handlers + dti[i].handler_off;
      int32_t count = read_sleb128(&handler);
      bool has_catchall = false;
      if (count <= 0) {
        count = -count;
        has_catchall = true;
      }
      while (count--) {
        uint32_t tidx = read_uleb128(&handler);
        uint32_t hoff = read_uleb128(&handler);
        DexType* dt = idx->get_typeidx(tidx);
        dextry->m_catches.push_back(std::make_pair(dt, hoff));
      }
      if (has_catchall) {
        auto hoff = read_uleb128(&handler);
        dextry->m_catches.push_back(std::make_pair(nullptr, hoff));
      }
      dc->m_tries.emplace_back(dextry);
    }
  }
  dc->m_dbg = DexDebugItem::get_dex_debug(idx, code->debug_info_off);
  return dc;
}
```

`DexInstruction`则相当于是指令, 看起来更想是java编译器一开始做的Tokenizer。

源码的dalvik目录下面则有java版本的对DEX文件的解析, 具体见: [>>> dalvik/dx/src/com/android/dex/Dex.java](https://j.mp/2zc16Ex)。