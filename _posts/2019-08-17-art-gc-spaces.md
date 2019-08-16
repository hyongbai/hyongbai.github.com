---
layout: post
title: "ART中各种Space及其创建和对象分配介绍"
description: "heap space of art gc"
category: all-about-tech
tags: -[aosp， art]
date: 2019-08-17 01:01:57+00:00
---

> 基于android-8.1.0_r60。

ART中有各种各样的Space，下面是 ***别人*** 制作的继承图。

![art gc heap spaces tree](https://t.cn/AiK31uy8)

透过这个图可以看出，除LargetObjectSpace以外全部都是物理空间上面连续的Space，即ContinuousSpace。并且所有的连续空间都会放到 `continuous_spaces_` 向量中。

所有的space都会在堆创建的过程中进行初始化，也就是heap的构造函数中都能找到创建过程。

这里只是大致介绍各个space作用以及如何创建/分配对象内存地址等，并**不详细说明**各个空间对象分配过程。GC相关的逻辑则不表。GC需要结合Collector来进行分析。

---

## 固定的Space类型

`Image Space` / `Zygote Space` / `Large Object Space` 这三种类型的space不论在何种类型的GC下面都会同时存在。

## Image Space

包括 `boot.oat` 和 `boot.art` ，这些image以向量的形式存储在 `boot_image_spaces_` 中。

Android Framework中通用的类都都是存储在这里的。

## Zygote Space

即 `zygote_space_` 对象，此空间的内存是不会进行回收的。

包含Zygote进程启动过程中创建的所有对象。这些对象是所有进程共享的。

## Large Object Space

即 `large_object_space_` 对象，用于加载大对象。简称 LOS，GC的日志中的 LOS 即是大对象。

#### LOS创建

创建过程如下:

先看看 runtime 的 `-XX:LargeObjectSpace=` 参数定义：

```cpp
// art/runtime/parsed_options.cc
.Define("-XX:LargeObjectSpace=_")
  .WithType<gc::space::LargeObjectSpaceType>()
  .WithValueMap({{"disabled", gc::space::LargeObjectSpaceType::kDisabled},
                 {"freelist", gc::space::LargeObjectSpaceType::kFreeList},
                 {"map",      gc::space::LargeObjectSpaceType::kMap}})
  .IntoKey(M::LargeObjectSpace)
```

之后在 runtime 初始化时(即Runtime::Init中)创建 heap，并获取 `Opt::LargeObjectSpace`参数，拿到LargeObjectSpaceType的值。之后在 heap 构造函数，根据LargeObjectSpaceType创建响应类型的 LOS。如下:

```cpp
// art/runtime/gc/heap.cc
// Allocate the large object space.
if (large_object_space_type == space::LargeObjectSpaceType::kFreeList) {
large_object_space_ = space::FreeListSpace::Create("free list large object space", nullptr,
                                                   capacity_);
CHECK(large_object_space_ != nullptr) << "Failed to create large object space";
} else if (large_object_space_type == space::LargeObjectSpaceType::kMap) {
large_object_space_ = space::LargeObjectMapSpace::Create("mem map large object space");
CHECK(large_object_space_ != nullptr) << "Failed to create large object space";
} else {
// Disable the large object space by making the cutoff excessively large.
large_object_threshold_ = std::numeric_limits<size_t>::max();
large_object_space_ = nullptr;
}
```

可以看到 LOS 分为两种：即 FreeList 和 LargeObjectMap。在Android-8.1.0上面，使用的是LargeObjectMap。

#### LOS分配

如果将要分配的对象 size 大于 `large_object_threshold_` 并且类型是 `primitiveArrary` 或者字符串，则会认为是大对象。

具体逻辑：

```cpp
// art/runtime/gc/heap-inl.h
inline bool Heap::ShouldAllocLargeObject(ObjPtr<mirror::Class> c, size_t byte_count) const {
  // We need to have a zygote space or else our newly allocated large object can end up in the
  // Zygote resulting in it being prematurely freed.
  // We can only do this for primitive objects since large objects will not be within the card table
  // range. This also means that we rely on SetClass not dirtying the object's card.
  return byte_count >= large_object_threshold_ && (c->IsPrimitiveArray() || c->IsStringClass());
}
```

其中`large_object_threshold_`的大小为3个 `PageSize`。一个 PageSize默认为4KB，也就是说默认超过 **`12KB`** 则被认定为大对象，如果是指定类型那么就会放在 `large object space`  中分配内存。

```cpp
// art/runtime/globals.sh
// System page size. We check this against sysconf(_SC_PAGE_SIZE) at runtime, but use a simple
// compile-time constant so the compiler can generate better code.
static constexpr int kPageSize = 4096;

// art/runtime/gc/heap-inl.h
static constexpr size_t kMinLargeObjectThreshold = 3 * kPageSize;
```

---

## 按需使用的Space类型

下面这些类型的Space是会根据不同的GC类型进行相应的创建的。

也就是说不同的GC的会对应者不同的spce，对应变量选择性初始化。始终不会同时存在。

比如CC对应的是`Region Space`，只有region_space_会被初始化，其他的space变量是不会进行赋值的。

## Region Space

`kCollectorTypeCC`即并行垃圾回收时会使用此空间来进行内存分配。在8.1上面，默认使用的是此种方式。对应的变量是 `region_space_` 。

#### Region Space创建

Region Space 会将当前的内存区域按照 `kRegionSize` 大小等分为若干个内存区域(称为Region)。其中 `kRegionSize` 大小为256kb。

源码：

```cpp
// art/runtime/gc/space/region_space.h
// The region size.
static constexpr size_t kRegionSize = 256 * KB;
```

Region Space 构造函数如下：

```cpp
// art/runtime/gc/space/region_space.cc
RegionSpace::RegionSpace(const std::string& name, MemMap* mem_map)
    : ContinuousMemMapAllocSpace(name, mem_map, mem_map->Begin(), mem_map->End(), mem_map->End(),
                                 kGcRetentionPolicyAlwaysCollect),
      region_lock_("Region lock", kRegionSpaceRegionLock), time_(1U) {
  size_t mem_map_size = mem_map->Size();
  CHECK_ALIGNED(mem_map_size, kRegionSize);
  CHECK_ALIGNED(mem_map->Begin(), kRegionSize);
  num_regions_ = mem_map_size / kRegionSize;
  num_non_free_regions_ = 0U;
  DCHECK_GT(num_regions_, 0U);
  non_free_region_index_limit_ = 0U;
  regions_.reset(new Region[num_regions_]);
  uint8_t* region_addr = mem_map->Begin();
  for (size_t i = 0; i < num_regions_; ++i, region_addr += kRegionSize) {
    regions_[i].Init(i, region_addr, region_addr + kRegionSize);
  }
  mark_bitmap_.reset(accounting::ContinuousSpaceBitmap::Create("region space live bitmap", Begin(), Capacity()));
  // ...
}
```

可以看到初始化的时候有上面说的region的分配规则。可以得出 RegionSpace 就是通过平均分配256kb的 region 来对内存进行分片管理。

#### Region Space分配对象

heap 在进行 Allocate 对象时，发现如果当前使用的是 region space 来进行分配，则调用 Region Space 的 `AllocNonvirtual` 函数。

如下：

```cpp
// art/runtime/gc/heap-inl.h
template <const bool kInstrumented, const bool kGrow>
inline mirror::Object* Heap::TryToAllocate(Thread* self,
                                           AllocatorType allocator_type,
                                           size_t alloc_size,
                                           size_t* bytes_allocated,
                                           size_t* usable_size,
                                           size_t* bytes_tl_bulk_allocated) {
    //...
    case kAllocatorTypeRegion: {
      DCHECK(region_space_ != nullptr);
      alloc_size = RoundUp(alloc_size, space::RegionSpace::kAlignment);
      ret = region_space_->AllocNonvirtual<false>(alloc_size,
                                                  bytes_allocated,
                                                  usable_size,
                                                  bytes_tl_bulk_allocated);
      break;
    }
    //...
}
```

`AllocNonvirtual` 其实是 region_space 中的一个内联函数。

因此我们可以去 `region_space-inl.h` 中去查看其具体实现逻辑。如下：

```cpp
// art/runtime/gc/space/region_space-inl.h
template<bool kForEvac>
inline mirror::Object* RegionSpace::AllocNonvirtual(size_t num_bytes, size_t* bytes_allocated,
                                                    size_t* usable_size,
                                                    size_t* bytes_tl_bulk_allocated) {
  DCHECK_ALIGNED(num_bytes, kAlignment);
  mirror::Object* obj;
  if (LIKELY(num_bytes <= kRegionSize)) {
    // Non-large object.
    obj = (kForEvac ? evac_region_ : current_region_)->Alloc(num_bytes,
                                                             bytes_allocated,
                                                             usable_size,
                                                             bytes_tl_bulk_allocated);
    if (LIKELY(obj != nullptr)) {
      return obj;
    }
    MutexLock mu(Thread::Current(), region_lock_);
    // Retry with current region since another thread may have updated it.
    obj = (kForEvac ? evac_region_ : current_region_)->Alloc(num_bytes,
                                                             bytes_allocated,
                                                             usable_size,
                                                             bytes_tl_bulk_allocated);
    if (LIKELY(obj != nullptr)) {
      return obj;
    }
    Region* r = AllocateRegion(kForEvac);
    if (LIKELY(r != nullptr)) {
      obj = r->Alloc(num_bytes, bytes_allocated, usable_size, bytes_tl_bulk_allocated);
      CHECK(obj != nullptr);
      // Do our allocation before setting the region, this makes sure no threads race ahead
      // and fill in the region before we allocate the object. b/63153464
      if (kForEvac) {
        evac_region_ = r;
      } else {
        current_region_ = r;
      }
      return obj;
    }
  } else {
    // Large object.
    obj = AllocLarge<kForEvac>(num_bytes, bytes_allocated, usable_size,
                               bytes_tl_bulk_allocated);
    if (LIKELY(obj != nullptr)) {
      return obj;
    }
  }
  return nullptr;
}
```

可以看到 region space 主要是通过管理 region对象 并使用 region对象 来进行内存分配的。

并且当要分配的对象大小大于regionSize即256kb时，regionSpace会单独处理内部的LargeSpace来进行分配(会以多个region拼接，并且后面的region被定义为kRegionStateLargeTail)。

> 思考：如何跳过LOS到RegionSpace的呢？

Region中普通对象分配过程如下：

```cpp
// art/runtime/gc/space/region_space-inl.h
inline mirror::Object* RegionSpace::Region::Alloc(size_t num_bytes, size_t* bytes_allocated,
                                                  size_t* usable_size,
                                                  size_t* bytes_tl_bulk_allocated) {
  DCHECK(IsAllocated() && IsInToSpace());
  DCHECK_ALIGNED(num_bytes, kAlignment);
  uint8_t* old_top;
  uint8_t* new_top;
  do {
    old_top = top_.LoadRelaxed();
    new_top = old_top + num_bytes;
    if (UNLIKELY(new_top > end_)) {
      return nullptr;
    }
  } while (!top_.CompareExchangeWeakRelaxed(old_top, new_top));
  objects_allocated_.FetchAndAddRelaxed(1);
  DCHECK_LE(Top(), end_);
  DCHECK_LT(old_top, end_);
  DCHECK_LE(new_top, end_);
  *bytes_allocated = num_bytes;
  if (usable_size != nullptr) {
    *usable_size = num_bytes;
  }
  *bytes_tl_bulk_allocated = num_bytes;
  return reinterpret_cast<mirror::Object*>(old_top);
}
```

在每个 `region` 中通过 `top_` 来管理当前的内存指针。当需要分配对象是，将 `top_` 往后面移动 `num_bytes`，如超过了当前 `region` 的 `end_` 区域则认为此 region 无足够空间。交给下一个 region 分配。

## BumpPointerSpace

移动GC即`MovingGc`时会使用`BumpPointerSpace`来分配内存(CC除外)。

其中 `bump_pointer_space_` 和 `temp_space_` 分别是 `from space` 和 `to space`。

并且在 `reclaim phase` 阶段进行会空间交换。

其中 MovingGC 的定义如下：

```cpp
// art/runtime/heap.cc
static bool IsMovingGc(CollectorType collector_type) {
return
    collector_type == kCollectorTypeSS ||
    collector_type == kCollectorTypeGSS ||
    collector_type == kCollectorTypeCC ||
    collector_type == kCollectorTypeCCBackground ||
    collector_type == kCollectorTypeMC ||
    collector_type == kCollectorTypeHomogeneousSpaceCompact;
}
```

可以看到SS/GSS/CC/MC/HomogeneousSpaceCompact(同构空间)都属于MovingGC。

#### BumpPointerSpace创建过程

``` cpp
// art/runtime/heap.cc
else if (IsMovingGc(foreground_collector_type_) &&
      foreground_collector_type_ != kCollectorTypeGSS) {
    bump_pointer_space_ = space::BumpPointerSpace::CreateFromMemMap("Bump pointer space 1", main_mem_map_1.release());
    AddSpace(bump_pointer_space_);
    temp_space_ = space::BumpPointerSpace::CreateFromMemMap("Bump pointer space 2", main_mem_map_2.release());
    AddSpace(temp_space_);
  } else {
    CreateMainMallocSpace(main_mem_map_1.release(), initial_size, growth_limit_, capacity_);
    AddSpace(main_space_);
    if (!separate_non_moving_space) {
      non_moving_space_ = main_space_;
    }
    if (foreground_collector_type_ == kCollectorTypeGSS) {
      CHECK_EQ(foreground_collector_type_, background_collector_type_);
      main_mem_map_2.release();
      bump_pointer_space_ = space::BumpPointerSpace::Create("Bump pointer space 1", kGSSBumpPointerSpaceCapacity,nullptr);
      AddSpace(bump_pointer_space_);
      temp_space_ = space::BumpPointerSpace::Create("Bump pointer space 2", kGSSBumpPointerSpaceCapacity, nullptr);
      CHECK(temp_space_ != nullptr);
      AddSpace(temp_space_);
    } else if (main_mem_map_2.get() != nullptr) {
      //。。。
    }
  }
```

#### BumpPointer 对象分配过程

入口还是在heap-inl.h的`TryToAllocate`函数中，如果是kAllocatorTypeBumpPointere则调用bump_pointer_spac的`AllocNonvirtual`。

```
// art/runtime/heap-inl.h
inline mirror::Object* Heap::TryToAllocate(Thread* self,
// ...
case kAllocatorTypeBumpPointer: {
  DCHECK(bump_pointer_space_ != nullptr);
  alloc_size = RoundUp(alloc_size, space::BumpPointerSpace::kAlignment);
  ret = bump_pointer_space_->AllocNonvirtual(alloc_size);
  if (LIKELY(ret != nullptr)) {
    *bytes_allocated = alloc_size;
    *usable_size = alloc_size;
    *bytes_tl_bulk_allocated = alloc_size;
  }
  break;
}

```

heap中调用了bump的AllocNonvirtual函数，来进行对象分配：

```
// art/runtime/gc/space/bump_pointer_space-inl.h
inline mirror::Object* BumpPointerSpace::AllocNonvirtualWithoutAccounting(size_t num_bytes) {
  DCHECK_ALIGNED(num_bytes, kAlignment);
  uint8_t* old_end;
  uint8_t* new_end;
  do {
    old_end = end_.LoadRelaxed();
    new_end = old_end + num_bytes;
    // If there is no more room in the region, we are out of memory.
    if (UNLIKELY(new_end > growth_end_)) {
      return nullptr;
    }
  } while (!end_.CompareExchangeWeakSequentiallyConsistent(old_end, new_end));
  return reinterpret_cast<mirror::Object*>(old_end);
}

inline mirror::Object* BumpPointerSpace::AllocNonvirtual(size_t num_bytes) {
  mirror::Object* ret = AllocNonvirtualWithoutAccounting(num_bytes);
  if (ret != nullptr) {
    objects_allocated_.FetchAndAddSequentiallyConsistent(1);
    bytes_allocated_.FetchAndAddSequentiallyConsistent(num_bytes);
  }
  return ret;
}
```

可以看到bump持有了一个_end变量，每次分配对象只是会往后移动`num_bytes`个字节，并且新的end超过能增加的上限`growth_end_`，则会直接返回nullptr表示分配失败。分配结束之后end_会往后移动，即通过CompareExchangeWeakSequentiallyConsistent给end_赋值。

## Malloc(Main) Space

如果垃圾回收不是 MovingGC 的时候，那么在 heap 的构造函数中就会创建`main_space_`。

同时在 art 中 `main_space_` 要么是 `rosalloc_space_` 要么就是 `dlmalloc_space_`，并且这两个变量不会同时存在。

![art-gc-heap-main-ros-ml-spaces.png](https://t.cn/Ai9VXA1h)

#### MallocSpace创建过程

- malloc_space

主要是通过`CreateMainMallocSpace`这个函数创建的:

```cpp
// art/runtime/gc/heap.cc
void Heap::CreateMainMallocSpace(MemMap* mem_map, size_t initial_size, size_t growth_limit,
                                 size_t capacity) {
  bool can_move_objects = IsMovingGc(background_collector_type_) !=
      IsMovingGc(foreground_collector_type_) || use_homogeneous_space_compaction_for_oom_;
  if (kCompactZygote && Runtime::Current()->IsZygote() && !can_move_objects) {
    can_move_objects = !HasZygoteSpace() && foreground_collector_type_ != kCollectorTypeGSS;
  }
  if (collector::SemiSpace::kUseRememberedSet && main_space_ != nullptr) {
    RemoveRememberedSet(main_space_);
  }
  const char* name = kUseRosAlloc ? kRosAllocSpaceName[0] : kDlMallocSpaceName[0];
  main_space_ = CreateMallocSpaceFromMemMap();
  SetSpaceAsDefault(main_space_);
}

space::MallocSpace* Heap::CreateMallocSpaceFromMemMap() {
  if (kUseRosAlloc) {
    malloc_space = space::RosAllocSpace::CreateFromMemMap();
  } else {
    malloc_space = space::DlMallocSpace::CreateFromMemMap();
  }
  //...
}
```

之后通过 `SetSpaceAsDefault` 给 `dlmalloc_space_` 或者 `rosalloc_space_`赋值：

```cpp
// art/runtime/gc/heap.cc
void Heap::SetSpaceAsDefault(space::ContinuousSpace* continuous_space) {
  WriterMutexLock mu(Thread::Current(), *Locks::heap_bitmap_lock_);
  if (continuous_space->IsDlMallocSpace()) {
    dlmalloc_space_ = continuous_space->AsDlMallocSpace();
  } else if (continuous_space->IsRosAllocSpace()) {
    rosalloc_space_ = continuous_space->AsRosAllocSpace();
  }
}
```

- kUseRosAlloc

而在 Android8.1中 `kUseRosAlloc` 始终为 **`true`**。

```cpp
// art/runtime/gc/heap.h
// If true, use rosalloc/RosAllocSpace instead of dlmalloc/DlMallocSpace
static constexpr bool kUseRosAlloc = true;
```

源码：[art/+/refs/tags/android-8.1.0_r63/runtime/gc/heap.h](https://android.googlesource.com/platform/art/+/refs/tags/android-8.1.0_r63/runtime/gc/heap.h)

也就是说8.1中main_space_始终使用的是RosAllocSpace。

- CreateFromMemMap

```cpp
// art/runtime/gc/space/rosalloc_space.cc
RosAllocSpace* RosAllocSpace::CreateFromMemMap(MemMap* mem_map, const std::string& name,
                                               size_t starting_size, size_t initial_size,
                                               size_t growth_limit, size_t capacity,
                                               bool low_memory_mode, bool can_move_objects) {
  DCHECK(mem_map != nullptr);

  bool running_on_memory_tool = Runtime::Current()->IsRunningOnMemoryTool();

  allocator::RosAlloc* rosalloc = CreateRosAlloc(mem_map->Begin(), starting_size, initial_size,
                                                 capacity, low_memory_mode, running_on_memory_tool);
  if (rosalloc == nullptr) {
    LOG(ERROR) << "Failed to initialize rosalloc for alloc space (" << name << ")";
    return nullptr;
  }

  // Protect memory beyond the starting size. MoreCore will add r/w permissions when necessory
  uint8_t* end = mem_map->Begin() + starting_size;
  if (capacity - starting_size > 0) {
    CHECK_MEMORY_CALL(mprotect, (end, capacity - starting_size, PROT_NONE), name);
  }

  // Everything is set so record in immutable structure and leave
  uint8_t* begin = mem_map->Begin();
  // TODO: Fix RosAllocSpace to support Valgrind/ASan. There is currently some issues with
  // AllocationSize caused by redzones. b/12944686
  if (running_on_memory_tool) {
    return new MemoryToolMallocSpace<RosAllocSpace, kDefaultMemoryToolRedZoneBytes, false, true>(
        mem_map, initial_size, name, rosalloc, begin, end, begin + capacity, growth_limit,
        can_move_objects, starting_size, low_memory_mode);
  } else {
    return new RosAllocSpace(mem_map, initial_size, name, rosalloc, begin, end, begin + capacity,
                             growth_limit, can_move_objects, starting_size, low_memory_mode);
  }
}
```

#### MallocSpace对象分配过程

在heap的分配函数中，如果当前的Allocator是kAllocatorTypeRosAlloc，那么使用RosAllocSpace。

```
// art/runtime/heap-inl.h
case kAllocatorTypeRosAlloc: {
  if (kInstrumented && UNLIKELY(is_running_on_memory_tool_)) {
    // If running on valgrind or asan, we should be using the instrumented path.
    size_t max_bytes_tl_bulk_allocated = rosalloc_space_->MaxBytesBulkAllocatedFor(alloc_size);
    if (UNLIKELY(IsOutOfMemoryOnAllocation(allocator_type,
                                           max_bytes_tl_bulk_allocated,
                                           kGrow))) {
      return nullptr;
    }
    ret = rosalloc_space_->Alloc(self, alloc_size, bytes_allocated, usable_size,
                                 bytes_tl_bulk_allocated);
  } else {
    DCHECK(!is_running_on_memory_tool_);
    size_t max_bytes_tl_bulk_allocated =
        rosalloc_space_->MaxBytesBulkAllocatedForNonvirtual(alloc_size);
    if (UNLIKELY(IsOutOfMemoryOnAllocation(allocator_type,
                                           max_bytes_tl_bulk_allocated,
                                           kGrow))) {
      return nullptr;
    }
    if (!kInstrumented) {
      DCHECK(!rosalloc_space_->CanAllocThreadLocal(self, alloc_size));
    }
    ret = rosalloc_space_->AllocNonvirtual(self,
                                           alloc_size,
                                           bytes_allocated,
                                           usable_size,
                                           bytes_tl_bulk_allocated);
  }
```

大概率上是会执行else中的AllocNonvirtual函数。如下：

```
// art/runtime/gc/space/rosalloc_space.h
mirror::Object* AllocNonvirtual(Thread* self, size_t num_bytes, size_t* bytes_allocated,
                              size_t* usable_size, size_t* bytes_tl_bulk_allocated) {
// RosAlloc zeroes memory internally.
return AllocCommon(self, num_bytes, bytes_allocated, usable_size,
                   bytes_tl_bulk_allocated);
}

// art/runtime/gc/space/rosalloc_space-inl.h
template<bool kThreadSafe>
inline mirror::Object* RosAllocSpace::AllocCommon(Thread* self, size_t num_bytes,
                                                  size_t* bytes_allocated, size_t* usable_size,
                                                  size_t* bytes_tl_bulk_allocated) {
  size_t rosalloc_bytes_allocated = 0;
  size_t rosalloc_usable_size = 0;
  size_t rosalloc_bytes_tl_bulk_allocated = 0;
  if (!kThreadSafe) {
    Locks::mutator_lock_->AssertExclusiveHeld(self);
  }
  mirror::Object* result = reinterpret_cast<mirror::Object*>(
      rosalloc_->Alloc<kThreadSafe>(self, num_bytes, &rosalloc_bytes_allocated,
                                    &rosalloc_usable_size,
                                    &rosalloc_bytes_tl_bulk_allocated));
  if (LIKELY(result != nullptr)) {
    if (kDebugSpaces) {
      CHECK(Contains(result)) << "Allocation (" << reinterpret_cast<void*>(result)
            << ") not in bounds of allocation space " << *this;
    }
    DCHECK(bytes_allocated != nullptr);
    *bytes_allocated = rosalloc_bytes_allocated;
    DCHECK_EQ(rosalloc_usable_size, rosalloc_->UsableSize(result));
    if (usable_size != nullptr) {
      *usable_size = rosalloc_usable_size;
    }
    DCHECK(bytes_tl_bulk_allocated != nullptr);
    *bytes_tl_bulk_allocated = rosalloc_bytes_tl_bulk_allocated;
  }
  return result;
}
```

其中AllocNonvirtual最终会调用AllocCommon以线程安全的方式执行。最终会通过内部持有的RosAlloc对象来进行分配。具体RosAlloc的分配过程比较复杂。

## 参考

- <http://paul.pub/android-art-vm>
- <https://juejin.im/post/59362bdbfe88c20061dccf30>
- <https://android.googlesource.com/platform/art/+/refs/tags/android-8.1.0_r63/>