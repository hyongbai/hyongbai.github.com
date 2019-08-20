---
layout: post
title: "RosAlloc对象分配过程"
description: "rosalloc in art gc"
category: all-about-tech
tags: -[aosp， art]
date: 2019-08-20 23:03:57+00:00
---

> 基于android-8.1.0_r60

RoaAlloc基于固定尺寸的Bracket来给对象进行分配。

> RosAlloc中Bracket目前有个翻译方式为箱子。

## BracketSize以及idx分配原则

下面是将会用到的常量：

```
// The magic number for a run.
static constexpr uint8_t kMagicNum = 42;
// The magic number for free pages.
static constexpr uint8_t kMagicNumFree = 43;
// The number of size brackets.
static constexpr size_t kNumOfSizeBrackets = 42;
// The sizes (the slot sizes, in bytes) of the size brackets. 
> - kMaxThreadLocalBracketSize = 128UL
> - kThreadLocalBracketQuantumSize = 8UL
> - kMaxRegularBracketSize = 512UL
> - kBracketQuantumSize = 16UL
> - kNumThreadLocalSizeBrackets = 16UL
> - kNumOfSizeBrackets = 42UL
```

Bracket的分配都是基于SizeToIndexAndBracketSize函数进行：

```cpp
// art/runtime/gc/allocator/rosalloc.h
// A combination of SizeToIndex() and RoundToBracketSize().
static size_t SizeToIndexAndBracketSize(size_t size, size_t* bracket_size_out) {
    DCHECK(size <= kLargeSizeThreshold);
    size_t idx;
    size_t bracket_size;
    if (LIKELY(size <= kMaxThreadLocalBracketSize)) {
      bracket_size = RoundUp(size, kThreadLocalBracketQuantumSize);
      idx = bracket_size / kThreadLocalBracketQuantumSize - 1;
    } else if (size <= kMaxRegularBracketSize) {
      bracket_size = RoundUp(size, kBracketQuantumSize);
      idx = ((bracket_size - kMaxThreadLocalBracketSize) / kBracketQuantumSize - 1)
          + kNumThreadLocalSizeBrackets;
    } else if (size <= 1 * KB) {
      bracket_size = 1 * KB;
      idx = kNumOfSizeBrackets - 2;
    } else {
      DCHECK(size <= 2 * KB);
      bracket_size = 2 * KB;
      idx = kNumOfSizeBrackets - 1;
    }
    DCHECK_EQ(idx, SizeToIndex(size)) << idx;
    DCHECK_EQ(bracket_size, IndexToBracketSize(idx)) << idx;
    DCHECK_EQ(bracket_size, bracketSizes[idx]) << idx;
    DCHECK_LE(size, bracket_size) << idx;
    DCHECK(size > kMaxRegularBracketSize ||
           (size <= kMaxThreadLocalBracketSize &&
            bracket_size - size < kThreadLocalBracketQuantumSize) ||
           (size <= kMaxRegularBracketSize && bracket_size - size < kBracketQuantumSize)) << idx;
    *bracket_size_out = bracket_size;
    return idx;
}
```

其实就是一系列的实现定义好的计算。

==**可以得出如下结论**==：

- size小于kMaxThreadLocalBracketSize(128)

> 则分配的Bracket的idx为 bracket_size / kThreadLocalBracketQuantumSize -1 即 **`0到15号`** Bracket。
>
> 也就是前16{即kNumThreadLocalSizeBrackets}个Bracket。

- size小于kMaxRegularBracketSize(512)

> 则分配的Bracket的idx为 ((bracket_size - kMaxThreadLocalBracketSize) / kBracketQuantumSize - 1) + kNumThreadLocalSizeBrackets。
>
> 也就是第16{即kNumThreadLocalSizeBrackets}到39{即kNumOfSizeBrackets - 3}号Bracket。

- size小于1KB，则对应的idx为40号{即kNumOfSizeBrackets - 2}


- size小于2KB，则对应的idx为41号{即kNumOfSizeBrackets - 1}


==**也就是说**==:


- 第0到15号Bracket，也就是前16{即kNumThreadLocalSizeBrackets}：

> 后面的Bracket都比前面大 8{即kThreadLocalBracketQuantumSize}。
>
> 每个大小为: (idx + 1) * 8{即kThreadLocalBracketQuantumSize}。

- 第16{即kNumThreadLocalSizeBrackets}到39{即kNumOfSizeBrackets - 2}号Bracket(共24个)：

> 后面的Bracket都比前面大 16{即kBracketQuantumSize}。
>
> 每个大小为: (idx + 1 - {即kNumThreadLocalSizeBrackets}) * 16{即kBracketQuantumSize} + 128{即kMaxThreadLocalBracketSize}。

- 第40{即kNumOfSizeBrackets - 2}号Bracket，大小为1KB。

- 第41{即kNumOfSizeBrackets - 1}号Bracket，大小为2KB。

==**总结来说**==

RosAlloc定义了42个Bracket。前16个的大小以8递增，接着的24个在前面基础(128)上以16递增，倒数两个为1KB和2KB。因此在RosAlloc中将超过2KB的认定为大对象(这与Heap中的LOS以3page即12KB不同)。

## 对象分配过程

RosAllocSpace对于对象的分配都交给了RosAllocator，都是从RosAlloc::Alloc开始。如下：

```cpp
// art/runtime/gc/allocator/rosallac-inl.h
template<bool kThreadSafe>
inline ALWAYS_INLINE void* RosAlloc::Alloc(Thread* self, size_t size, size_t* bytes_allocated,
                                           size_t* usable_size,
                                           size_t* bytes_tl_bulk_allocated) {
  if (UNLIKELY(size > kLargeSizeThreshold)) {
    return AllocLargeObject(self, size, bytes_allocated, usable_size, bytes_tl_bulk_allocated);
  }
  void* m;
  if (kThreadSafe) {
    m = AllocFromRun(self, size, bytes_allocated, usable_size, bytes_tl_bulk_allocated);
  } else {
    m = AllocFromRunThreadUnsafe(self, size, bytes_allocated, usable_size,
                                 bytes_tl_bulk_allocated);
  }
  // Check if the returned memory is really all zero.
  if (ShouldCheckZeroMemory() && m != nullptr) {
    uint8_t* bytes = reinterpret_cast<uint8_t*>(m);
    for (size_t i = 0; i < size; ++i) {
      DCHECK_EQ(bytes[i], 0);
    }
  }
  return m;
}
```

如果需要分配对象的size大于kLargeSizeThreshold则使用RosAlloc的大对象分配策略(即通过AllocLargeObject)来分配对象。

即RosAlloc中也定义了自己的LargeObject，大小为kLargeSizeThreshold，即2KB。

因此在ros中存在三种类型的分配方式：

- 大对象：超过2KB(不含)，`AllocLargeObject`。
- 线程安全分配对象：小于等于2KB，`AllocFromRun`。
- 线程不安全分配对象: 小于等于2KB，`AllocFromRunThreadUnsafe`。

## 分配大对象

RosAlloc中大对象分配，经过如下函数：

```
// art/runtime/globals.h
// System page size. We check this against sysconf(_SC_PAGE_SIZE) at runtime, but use a simple
// compile-time constant so the compiler can generate better code.
static constexpr int kPageSize = 4096;

// art/runtime/gc/allocator/rosalloc.cc
void* RosAlloc::AllocLargeObject(Thread* self, size_t size, size_t* bytes_allocated,
                                 size_t* usable_size, size_t* bytes_tl_bulk_allocated) {
  // ...
  size_t num_pages = RoundUp(size, kPageSize) / kPageSize;
  void* r;
  {
    MutexLock mu(self, lock_);
    r = AllocPages(self, num_pages, kPageMapLargeObject);
  }
  // ...
  return r;
}
```

这里的page使用的是art中的全局定义，一个pagesize为4k(通LOS中的page大小)。RosAlloc以page为最小单位来进行分块，上面的逻辑是计算出自己所需要的page数量。也就是说RosAlloc的大对象是以Page级别直接进行分配的。

> 疑问：如果大量的对象都是在2kb到4kb之间但是仍然分配一个Page，这么分配对象岂不是很浪费空间吗？

然后通过num_pages算出`req_byte_size`再分配，如下：

> AllocPages(Thread* self, size_t num_pages, uint8_t page_map_type)函数接近200行，拆成3步来看。
> - 步骤一: 通过req_byte_size拿到FreePageRun
> - 步骤二: 处理FreePageRun异常情况(UNLIKELY)
> - 步骤三: 标记Page

#### 步骤一: AllocPages：分配FreePageRun

```
// art/runtime/gc/allocator/rosalloc.cc
void* RosAlloc::AllocPages(Thread* self, size_t num_pages, uint8_t page_map_type) {
  lock_.AssertHeld(self);
  FreePageRun* res = nullptr;
  const size_t req_byte_size = num_pages * kPageSize;
  for (auto it = free_page_runs_.begin(); it != free_page_runs_.end(); ) {
    FreePageRun* fpr = *it;
    size_t fpr_byte_size = fpr->ByteSize(this);
    DCHECK_EQ(fpr_byte_size % kPageSize, static_cast<size_t>(0));
    if (req_byte_size <= fpr_byte_size) {
      it = free_page_runs_.erase(it);
      if (req_byte_size < fpr_byte_size) {
        FreePageRun* remainder = reinterpret_cast<FreePageRun*>(reinterpret_cast<uint8_t*>(fpr) + req_byte_size);
        remainder->SetByteSize(this, fpr_byte_size - req_byte_size);
        free_page_runs_.insert(remainder);
        fpr->SetByteSize(this, req_byte_size);
      }
      res = fpr;
      break;
    } else {
      ++it;
    }
  }
```

原则就是遍历free_page_runs_找到大于等于当前所需分配大小的FreePageRun。这个过程比较简单。

需要注意的是，如果大于req_byte_size则会将当前的FreePageRun给拆分掉，并且把拆分完出来的`remainder`重新加入到列表中，用以再次分配。虽名字带Run，但是与下面的Run对象无关。

- free_page_runs 初始化

```cpp
// art/runtime/gc/allocator/rosalloc.cc
RosAlloc::RosAlloc(void* base, size_t capacity, size_t max_capacity,
                   PageReleaseMode page_release_mode, bool running_on_memory_tool,
                   size_t page_release_size_threshold)
  // ...
  FreePageRun* free_pages = reinterpret_cast<FreePageRun*>(base_);
  if (kIsDebugBuild) {
    free_pages->magic_num_ = kMagicNumFree;
  }
  free_pages->SetByteSize(this, capacity_);
  DCHECK_EQ(capacity_ % kPageSize, static_cast<size_t>(0));
  DCHECK(free_pages->IsFree());
  free_pages->ReleasePages(this);
  DCHECK(free_pages->IsFree());
  free_page_runs_.insert(free_pages);
}
```

在RosAlloc构造函数中，实现会创建新的FreePageRun，并将其SetByteSize设置为capacity_。同时将其插入到free_page_runs_。也就是说，此时free_page_runs_虽然只有一个FreePageRun，但这是大到不能再大的FreePageRun。

之后在回收之前，没分配一个对象都要从这里切割一块，同时生成一个新的FreePageRun。

#### 步骤三: AllocPages：标记Page

```
// art/runtime/gc/allocator/rosalloc.cc
void* RosAlloc::AllocPages(Thread* self, size_t num_pages, uint8_t page_map_type) {
  // ...
  if (LIKELY(res != nullptr)) {
    // Update the page map.
    size_t page_map_idx = ToPageMapIndex(res);
    // ...
    switch (page_map_type) {
    case kPageMapRun:
      page_map_[page_map_idx] = kPageMapRun;
      for (size_t i = 1; i < num_pages; i++) {
        page_map_[page_map_idx + i] = kPageMapRunPart;
      }
      break;
    case kPageMapLargeObject:
      page_map_[page_map_idx] = kPageMapLargeObject;
      for (size_t i = 1; i < num_pages; i++) {
        page_map_[page_map_idx + i] = kPageMapLargeObjectPart;
      }
      break;
    default:
      LOG(FATAL) << "Unreachable - page map type: " << static_cast<int>(page_map_type);
      break;
    }
    // ...
    return res;
  }
```

可以看到上面的FreePageRun其实是包含了包含了多个page的集合体。当某个run被分配之后，相对应位置的首个个page将会被设置为'kPageMapRun'或者'kPageMapLargeObject'，其他的page被设定为'kPageMapRunPart'或者'kPageMapLargeObjectPart'。


- `page_map_`, 用于标记ros_space上面各个Page的状态：

```cpp
// art/runtime/gc/allocator/rosalloc.h
 enum PageMapKind {
    kPageMapReleased = 0,     // Zero and released back to the OS.
    kPageMapEmpty,            // Zero but probably dirty.
    kPageMapRun,              // The beginning of a run.
    kPageMapRunPart,          // The non-beginning part of a run.
    kPageMapLargeObject,      // The beginning of a large object.
    kPageMapLargeObjectPart,  // The non-beginning part of a large object.
  };
```

#### 步骤二: AllocPages：处理FreePageRun异常-扩容

> capacity_在space创建时通过SetFootprintLimit()设置为当前MemMap的大小。
>
> 在Art中，capacity_表示当前内存空间的上限，footprint_表示可分配内存空间的上限。
>
> 也就是说在OOM之前，footprint_总是小于capacity_的。

注意，第一步分配失败并不代表内存用完了。它只能说明没有合适大小的FreePageRun来分配对象而已。既然说RosAlloc大对象都是通过FreePageRun来分配的，那么既然当前使用的FreePageRun都不够分配怎么办呢？

所以，既然都小，那么扩容就行了。因此接下来需要从free_page_runs取出末尾的一个，然后将这个对象重新设定内存尺寸。

因此，在这里其实会做三件事：

- 一是获取last_free_page_run。
- 二是重新分配内存
- 重新执行步骤一

下面是扩容的具体代码：

```cpp
// art/runtime/gc/allocator/rosalloc.cc
void* RosAlloc::AllocPages(Thread* self, size_t num_pages, uint8_t page_map_type) {
  // ...
  // Failed to allocate pages. Grow the footprint, if possible.
  if (UNLIKELY(res == nullptr && capacity_ > footprint_)) {
    FreePageRun* last_free_page_run = nullptr;
    size_t last_free_page_run_size;
    auto it = free_page_runs_.rbegin(); // reverse_iterator(end())
    if (it != free_page_runs_.rend() && (last_free_page_run = *it)->End(this) == base_ + footprint_) {
      // ...
      last_free_page_run_size = last_free_page_run->ByteSize(this);
    } else {
      // There is no free page run at the end.
      last_free_page_run_size = 0;
    }
    // 以上为获取last_free_page_run
    DCHECK_LT(last_free_page_run_size, req_byte_size);
    if (capacity_ - footprint_ + last_free_page_run_size >= req_byte_size) {
      // If we grow the heap, we can allocate it.
      size_t increment = std::min(std::max(2 * MB, req_byte_size - last_free_page_run_size),
                                  capacity_ - footprint_);
      DCHECK_EQ(increment % kPageSize, static_cast<size_t>(0));
      size_t new_footprint = footprint_ + increment;
      size_t new_num_of_pages = new_footprint / kPageSize;
      // ...
      page_map_size_ = new_num_of_pages;
      DCHECK_LE(page_map_size_, max_page_map_size_);
      free_page_run_size_map_.resize(new_num_of_pages);
      ArtRosAllocMoreCore(this, increment);
      if (last_free_page_run_size > 0) {
        // There was a free page run at the end. Expand its size.
        DCHECK_EQ(last_free_page_run_size, last_free_page_run->ByteSize(this));
        last_free_page_run->SetByteSize(this, last_free_page_run_size + increment);
        // ...
      } else {
        // Otherwise, insert a new free page run at the end.
        FreePageRun* new_free_page_run = reinterpret_cast<FreePageRun*>(base_ + footprint_);
        // ...
        new_free_page_run->SetByteSize(this, increment);
        DCHECK_EQ(new_free_page_run->ByteSize(this) % kPageSize, static_cast<size_t>(0));
        free_page_runs_.insert(new_free_page_run);
        // ...
      }
      // 以上为重新分配内存
      // ...
      footprint_ = new_footprint;
      // And retry the last free page run.
      it = free_page_runs_.rbegin();
      DCHECK(it != free_page_runs_.rend());
      FreePageRun* fpr = *it;
      // ...
      size_t fpr_byte_size = fpr->ByteSize(this);
      // ...
      free_page_runs_.erase(fpr);
      // ...
      if (req_byte_size < fpr_byte_size) {
        // Split if there's a remainder.
        FreePageRun* remainder = reinterpret_cast<FreePageRun*>(reinterpret_cast<uint8_t*>(fpr) + req_byte_size);
        // ...
        remainder->SetByteSize(this, fpr_byte_size - req_byte_size);
        DCHECK_EQ(remainder->ByteSize(this) % kPageSize, static_cast<size_t>(0));
        free_page_runs_.insert(remainder);
        // ...
        fpr->SetByteSize(this, req_byte_size);
        DCHECK_EQ(fpr->ByteSize(this) % kPageSize, static_cast<size_t>(0));
      }
      res = fpr;
    }
  }
```

第一步，在获取last_free_page_run时它的尾巴必须是在当前内存对齐，否则认为没有适用的FreePageRun。

第二步，首先会通过下面的算法算出increment：

```
std::min(std::max(2 * MB, req_byte_size - last_free_page_run_size), capacity_ - footprint_)
```

可以看出，这里的扩容上限最大不会超过2MB。

> 如果increment超过2MB怎么办，岂不是会直接分配失败吗？
> 其实不用担心，在heap中还存在LOS(LargeObjectSpace)专门用来处理大对象，也就是3 Page Size的对象。也就是说超过12kb的对象是不会通过RosAlloc分配的，更不用说2MB的对象了。
>
> 大对象仅仅包含primitive/String对象。

接着会重新计算footprint_(new_footprint)/page_map_size_/free_page_run_size_map_，并且通过ArtRosAllocMoreCore重新设置RosAllocSpace的End。

接着发现如果有适用的FreePageRun，那么基于之前的End(base_ + footprint_)地址创建一个大小为increment的新FreePageRun并插到最后。

第三步，代码逻辑同以上的“步骤一: AllocPages：分配FreePageRun”一致。为何不给这里的逻辑拆分出去呢？？

> 疑问：为何last_free_page_run必须用完footprint_才对这个对象扩容，否则就创建一个新的page_run插在最后?

## 线程安全分配对象

这里分配对象时是通过Run这个集合体来管理和分配内存的。而Run本身其实是有n个page大小的一块内存区域，这个区域会包含复杂的数据结构。

#### Run结构

Run的内存布局结构如下：

```
// Represents a run of memory slots of the same size.
//
// A run's memory layout:
//
// +-------------------+
// | magic_num         |
// +-------------------+
// | size_bracket_idx  |
// +-------------------+
// | is_thread_local   |
// +-------------------+
// | to_be_bulk_freed  |
// +-------------------+
// |                   |
// | free list         |
// |                   |
// +-------------------+
// |                   |
// | bulk free list    |
// |                   |
// +-------------------+
// |                   |
// | thread-local free |
// | list              |
// |                   |
// +-------------------+
// | padding due to    |
// | alignment         |
// +-------------------+
// | slot 0            |
// +-------------------+
// ...
// +-------------------+
// | last slot         |
// +-------------------+
//
```

- slot

```cpp
// art/runtime/gc/allocator/rosalloc.h
  // The slot header.
  class Slot {
   public:
    Slot* Next() const {
      return next_;
    }
    void SetNext(Slot* next) {
      next_ = next;
    }
    // The slot right before this slot in terms of the address.
    Slot* Left(size_t bracket_size) {
      return reinterpret_cast<Slot*>(reinterpret_cast<uintptr_t>(this) - bracket_size);
    }
    void Clear() {
      next_ = nullptr;
    }

   private:
    Slot* next_;  // Next slot in the list.
    friend class RosAlloc;
  };
  
  
Slot* FirstSlot() const {
  const uint8_t idx = size_bracket_idx_;
  return reinterpret_cast<Slot*>(reinterpret_cast<uintptr_t>(this) + headerSizes[idx]);
}

Slot* LastSlot() {
  const uint8_t idx = size_bracket_idx_;
  const size_t bracket_size = bracketSizes[idx];
  uintptr_t end = reinterpret_cast<uintptr_t>(End());
  Slot* last_slot = reinterpret_cast<Slot*>(end - bracket_size);
  DCHECK_LE(FirstSlot(), last_slot);
  return last_slot;
}

```

其实意味着在分配时bracket等于slot。bracket只是一个抽象的概念，而slot是对bracket的具象化。
slot是以bracket_size向左偏移来完成新slot创建的。

- free list

Run本身没有构造函数，它会在创建完成之后调用InitFreeList()完成初始化。

```cpp
// art/runtime/gc/allocator/rosalloc.h

void InitFreeList() {
  const uint8_t idx = size_bracket_idx_;
  const size_t bracket_size = bracketSizes[idx];
  Slot* first_slot = FirstSlot();
  // Add backwards so the first slot is at the head of the list.
  for (Slot* slot = LastSlot(); slot >= first_slot; slot = slot->Left(bracket_size)) {
    free_list_.Add(slot);
  }
}
```

这里首先会生成FirstSlot以及LastSlot，并从LastSlot开始往前逐个生成新slot并添加到free_list_当中。

换言之，free_list_是以倒序存储slot的。

- bulk free list

gc时会通过BulkFree()回收，并将这种回收出来的runs放到此列表中。

之后通过MergeBulkFreeListToFreeList()将列表合并到free_list_。

- thread-local free list 

> - FreeFromRun(仅能被Free()函数调用)判断如果IsThreadLocal()则AddToThreadLocalFreeList。
>
> - RevokeThreadLocalRuns时会调用MergeThreadLocalFreeListToFreeList自动合并到`free_list_`中。

## AllocFromRun

在分析之前可能会涉及到如下一些对象：

这些变量的部分定义可在RosAlloc::Initialize()找到。

- idx为bracket index，即根据对象大小通过SizeToIndexAndBracketSize计算出来的。
- `current_runs_[idx]`，可以理解为包含同一idx类型的多个bracket集合的run的集合。
- `numOfSlots[idx]`，idx对应的run中的slot数量。
- `numOfPages[idx]`，idx对应的Run中的Page的数量(真实反应一个Run的真实大小)
- `bracketSizes[idx]`，idx对应的braket的大小。
- `headerSizes`，idx对应的Run的header大小。

```
// art/runtime/gc/allocator/rosalloc.cc
void* RosAlloc::AllocFromRun(Thread* self, size_t size, size_t* bytes_allocated,
                             size_t* usable_size, size_t* bytes_tl_bulk_allocated) {
  // ...
  size_t bracket_size;
  size_t idx = SizeToIndexAndBracketSize(size, &bracket_size);
  void* slot_addr;
  if (LIKELY(idx < kNumThreadLocalSizeBrackets)) {
    // Use a thread-local run.
    Run* thread_local_run = reinterpret_cast<Run*>(self->GetRosAllocRun(idx));
    // Allow invalid since this will always fail the allocation.
    // ...
    slot_addr = thread_local_run->AllocSlot();
    // ...
    if (UNLIKELY(slot_addr == nullptr)) {
      // The run got full. Try to free slots.
      DCHECK(thread_local_run->IsFull());
      MutexLock mu(self, *size_bracket_locks_[idx]);
      bool is_all_free_after_merge;
      // This is safe to do for the dedicated_full_run_ since the bitmaps are empty.
      if (thread_local_run->MergeThreadLocalFreeListToFreeList(&is_all_free_after_merge)) {
        // ...
      } else {
        // No slots got freed. Try to refill the thread-local run.
        DCHECK(thread_local_run->IsFull());
        if (thread_local_run != dedicated_full_run_) {
          thread_local_run->SetIsThreadLocal(false);
          // ...
        }
        thread_local_run = RefillRun(self, idx);
        if (UNLIKELY(thread_local_run == nullptr)) {
          self->SetRosAllocRun(idx, dedicated_full_run_);
          return nullptr;
        }
        // ...
        thread_local_run->SetIsThreadLocal(true);
        self->SetRosAllocRun(idx, thread_local_run);
        DCHECK(!thread_local_run->IsFull());
      }
      // ...
      // Account for all the free slots in the new or refreshed thread local run.
      *bytes_tl_bulk_allocated = thread_local_run->NumberOfFreeSlots() * bracket_size;
      slot_addr = thread_local_run->AllocSlot();
      // Must succeed now with a new run.
      DCHECK(slot_addr != nullptr);
    } else {
      // The slot is already counted. Leave it as is.
      *bytes_tl_bulk_allocated = 0;
    }
    // ...
    *bytes_allocated = bracket_size;
    *usable_size = bracket_size;
  } else {
    // Use the (shared) current run.
    MutexLock mu(self, *size_bracket_locks_[idx]);
    slot_addr = AllocFromCurrentRunUnlocked(self, idx);
    // ...
    if (LIKELY(slot_addr != nullptr)) {
      *bytes_allocated = bracket_size;
      *usable_size = bracket_size;
      *bytes_tl_bulk_allocated = bracket_size;
    }
  }
  return slot_addr;
}
```

可以看到这里会通过size根据**BracketSize以及idx分配原则**计算出bracket对应的idx以及实际分配的bracket_size。

在实际分配时会存在两种情况：

- 当idx小于kNumThreadLocalSizeBrackets(16)时(即小于128字节)，使用线程内部的RosAllocRun
- 否则使用RosAlloc本身的`current_runs_`，即通过AllocFromCurrentRunUnlocked函数分配。

其实最终的实现逻辑时一致的。流程如下：

- current_run->AllocSlot直接分配。
- 分配失败(即slot用完)则重新分配空间。
- - 小于128字节的情况，则进行`free slots`动作，将线程的free slot合并到Run中的free _list。即`MergeThreadLocalFreeListToFreeList`
- - 否则则表示slot全部用完，则重新分配Run。分配新的Page用以填充Run。
- 再次使用AllocSlot进行分配。

> AllocFromCurrentRunUnlocked的实现等价于if (LIKELY(idx < kNumThreadLocalSizeBrackets))。略去。

#### 分配细节

##### AllocSlot

```cpp
// art/runtime/gc/allocator/rosalloc-inl.h
inline void* RosAlloc::Run::AllocSlot() {
  Slot* slot = free_list_.Remove();
  if (kTraceRosAlloc && slot != nullptr) {
    const uint8_t idx = size_bracket_idx_;
    LOG(INFO) << "RosAlloc::Run::AllocSlot() : " << slot
              << ", bracket_size=" << std::dec << bracketSizes[idx]
              << ", slot_idx=" << SlotIndex(slot);
  }
  return slot;
}
```

这里的逻辑相当简单，就是从当前的free_list_中取出一个slot并返回。有此可知slot的大小并不固定，它是随着idx变化而变化。也就是说bracket就是这里的slot。

##### Free Slots

```cpp
// art/runtime/gc/allocator/rosalloc.cc
inline bool RosAlloc::Run::MergeThreadLocalFreeListToFreeList(bool* is_all_free_after_out) {
  DCHECK(IsThreadLocal());
  // Merge the thread local free list into the free list and clear the thread local free list.
  const uint8_t idx = size_bracket_idx_;
  bool thread_local_free_list_size = thread_local_free_list_.Size();
  const size_t size_before = free_list_.Size();
  free_list_.Merge(&thread_local_free_list_);
  const size_t size_after = free_list_.Size();
  DCHECK_EQ(size_before < size_after, thread_local_free_list_size > 0);
  DCHECK_LE(size_before, size_after);
  *is_all_free_after_out = free_list_.Size() == numOfSlots[idx];
  // Return true at least one slot was added to the free list.
  return size_before < size_after;
}
```

这里的逻辑就是把Run中thread_local_free_list_的内容填充到free_list_中去。并且通过最终free_list_的大小是否变化来判断是否合并成功。

##### Refill

```cpp
// art/runtime/gc/allocator/rosalloc.cc
RosAlloc::Run* RosAlloc::RefillRun(Thread* self, size_t idx) {
  // Get the lowest address non-full run from the binary tree.
  auto* const bt = &non_full_runs_[idx];
  if (!bt->empty()) {
    // If there's one, use it as the current run.
    auto it = bt->begin();
    Run* non_full_run = *it;
    DCHECK(non_full_run != nullptr);
    DCHECK(!non_full_run->IsThreadLocal());
    bt->erase(it);
    return non_full_run;
  }
  // If there's none, allocate a new run and use it as the current run.
  return AllocRun(self, idx);
}
```

不难得出RefillRun分两种情况获得可用的Run：

- `non_full_runs_`

记录的是已经分配了的并且被回收之后的Run。从而实现回收利用。大概会有如下入口：

> - RevokeRun: RevokeAllThreadLocalRuns() -> RevokeThreadLocalRuns()/RevokeThreadUnsafeCurrentRuns()
> - FreeFromRun: Free() -> FreeInternal() -> FreePages() / FreeFromRun()（BulkFree()不会调用FreeFromRun）
> - BulkFree: RosAllocSpace::FreeList() -> BulkFree()

- `AllocRun`

```cpp
// art/runtime/gc/allocator/rosalloc.cc
RosAlloc::Run* RosAlloc::AllocRun(Thread* self, size_t idx) {
  RosAlloc::Run* new_run = nullptr;
  {
    MutexLock mu(self, lock_);
    new_run = reinterpret_cast<Run*>(AllocPages(self, numOfPages[idx], kPageMapRun));
  }
  if (LIKELY(new_run != nullptr)) {
    new_run->size_bracket_idx_ = idx;
    if (kUsePrefetchDuringAllocRun && idx < kNumThreadLocalSizeBrackets) {
      if (kPrefetchNewRunDataByZeroing) {
        new_run->ZeroData();
      } else {
        const size_t num_of_slots = numOfSlots[idx];
        const size_t bracket_size = bracketSizes[idx];
        const size_t num_of_bytes = num_of_slots * bracket_size;
        uint8_t* begin = reinterpret_cast<uint8_t*>(new_run) + headerSizes[idx];
        for (size_t i = 0; i < num_of_bytes; i += kPrefetchStride) {
          __builtin_prefetch(begin + i);
        }
      }
    }
    new_run->InitFreeList();
  }
  return new_run;
}
```

AllocRun其实是通过AllocPages分配对应数量的pages(这里的逻辑跟上面**大对象分配**流程一致)。

完成这一步之后会再通过AllocSlot进行分配。

#### 小结

- 当需要分配的对象小于128字节，即idx小于16时。会使用线程中的Run进行分配，如果分配失败那么使用此run种的thread_local中的free slot进行分配。

- 否则使用从Space查找Run。

- 如果Run完全不能分配，则重新分配Page并创建新的Run。

## 线程不安全分配对象

```
// art/runtime/gc/allocator/rosalloc.cc
void* RosAlloc::AllocFromRunThreadUnsafe(Thread* self, size_t size, size_t* bytes_allocated,
                                         size_t* usable_size,
                                         size_t* bytes_tl_bulk_allocated) {
  DCHECK(bytes_allocated != nullptr);
  DCHECK(usable_size != nullptr);
  DCHECK(bytes_tl_bulk_allocated != nullptr);
  DCHECK_LE(size, kLargeSizeThreshold);
  size_t bracket_size;
  size_t idx = SizeToIndexAndBracketSize(size, &bracket_size);
  Locks::mutator_lock_->AssertExclusiveHeld(self);
  void* slot_addr = AllocFromCurrentRunUnlocked(self, idx);
  if (LIKELY(slot_addr != nullptr)) {
    *bytes_allocated = bracket_size;
    *usable_size = bracket_size;
    *bytes_tl_bulk_allocated = bracket_size;
  }
  // Caller verifies that it is all 0.
  return slot_addr;
}
```

这里就是上面说的第二种情况，即通过AllocFromCurrentRunUnlocked实现分配。无非就是没有持有size_bracket_locks_[idx]锁，即：

```
MutexLock mu(self, *size_bracket_locks_[idx]);
```

## 总结

> - 问题一: 为何使用线程中的Run分配？
> - 问题二: RosAlloc为何独立于LOS之外单独以Page为单位分配大对象？
> - 问题三: Run中的free_slots和thread_local_free_slots有何区别？
> - 问题四: 线程的Run与RosAllocSpace有何关系(并且此Run在当前Space生成)？