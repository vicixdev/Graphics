#ifndef CMN_ATOMIC_H
#define CMN_ATOMIC_H

// Memory ordering constraints for atomic operations.
typedef enum CmnMemoryOrder {
	CMN_RELAXED,
	CMN_ACQUIRE,
	CMN_CONSUME,
	CMN_RELEASE,
	CMN_ACQ_REL,
	CMN_SEQ_CST
} CmnMemoryOrder;

// Atomically loads a value.
//
// Inputs:
// - ptr: Pointer to atomic storage.
// - order: Memory ordering constraint.
//
// Returns:
// - Loaded value.
template <typename T> T cmnAtomicLoad(T* ptr, CmnMemoryOrder order = CMN_SEQ_CST);

// Atomically stores a value.
//
// Inputs:
// - ptr: Pointer to atomic storage.
// - value: Value to store.
// - order: Memory ordering constraint.
template <typename T> void cmnAtomicStore(T* ptr, T value, CmnMemoryOrder order = CMN_SEQ_CST);

// Atomically stores value and returns the previous value.
//
// Inputs:
// - ptr: Pointer to atomic storage.
// - value: Value to store.
// - order: Memory ordering constraint.
//
// Returns:
// - Previous value.
template <typename T> T cmnAtomicExchange(T* ptr, T value, CmnMemoryOrder order = CMN_SEQ_CST);

// Performs a strong compare-and-exchange.
//
// Inputs:
// - ptr: Pointer to atomic storage.
// - expected: Expected value.
// - value: Value written on success.
// - successOrder: Memory order used on success.
// - failureOrder: Memory order used on failure.
//
// Returns:
// - true when the exchange succeeds.
template <typename T> bool cmnAtomicCompareExchangeStrong(T* ptr, T expected, T value, CmnMemoryOrder successOrder = CMN_SEQ_CST, CmnMemoryOrder failureOrder = CMN_SEQ_CST);

// Performs a weak compare-and-exchange.
//
// Inputs:
// - ptr: Pointer to atomic storage.
// - expected: Expected value.
// - value: Value written on success.
// - successOrder: Memory order used on success.
// - failureOrder: Memory order used on failure.
//
// Returns:
// - true when the exchange succeeds.
template <typename T> bool cmnAtomicCompareExchangeWeak(T* ptr, T expected, T value, CmnMemoryOrder successOrder = CMN_SEQ_CST, CmnMemoryOrder failureOrder = CMN_SEQ_CST);

// Performs a strong compare-and-exchange.
//
// Inputs:
// - ptr: Pointer to atomic storage.
// - expected: In/out expected value, updated on failure.
// - value: Value written on success.
// - successOrder: Memory order used on success.
// - failureOrder: Memory order used on failure.
//
// Returns:
// - true when the exchange succeeds.
template <typename T> bool cmnAtomicCompareExchangeStrong(T* ptr, T* expected, T value, CmnMemoryOrder successOrder = CMN_SEQ_CST, CmnMemoryOrder failureOrder = CMN_SEQ_CST);

// Performs a weak compare-and-exchange.
//
// Inputs:
// - ptr: Pointer to atomic storage.
// - expected: In/out expected value, updated on failure.
// - value: Value written on success.
// - successOrder: Memory order used on success.
// - failureOrder: Memory order used on failure.
//
// Returns:
// - true when the exchange succeeds.
template <typename T> bool cmnAtomicCompareExchangeWeak(T* ptr, T* expected, T value, CmnMemoryOrder successOrder = CMN_SEQ_CST, CmnMemoryOrder failureOrder = CMN_SEQ_CST);

// Atomically adds value to *ptr.
//
// Inputs:
// - ptr: Pointer to atomic storage.
// - value: Addend.
// - order: Memory ordering constraint.
template <typename T> T cmnAtomicAdd(T* ptr, T value, CmnMemoryOrder order = CMN_SEQ_CST);

// Atomically subtracts value from *ptr.
//
// Inputs:
// - ptr: Pointer to atomic storage.
// - value: Subtrahend.
// - order: Memory ordering constraint.
template <typename T> void cmnAtomicSub(T* ptr, T value, CmnMemoryOrder order = CMN_SEQ_CST);

// Atomically applies bitwise AND.
//
// Inputs:
// - ptr: Pointer to atomic storage.
// - value: Operand.
// - order: Memory ordering constraint.
template <typename T> void cmnAtomicAnd(T* ptr, T value, CmnMemoryOrder order = CMN_SEQ_CST);

// Atomically applies bitwise NAND.
//
// Inputs:
// - ptr: Pointer to atomic storage.
// - value: Operand.
// - order: Memory ordering constraint.
template <typename T> void cmnAtomicNand(T* ptr, T value, CmnMemoryOrder order = CMN_SEQ_CST);

// Atomically applies bitwise OR.
//
// Inputs:
// - ptr: Pointer to atomic storage.
// - value: Operand.
// - order: Memory ordering constraint.
template <typename T> void cmnAtomicOr(T* ptr, T value, CmnMemoryOrder order = CMN_SEQ_CST);

// Atomically applies bitwise XOR.
//
// Inputs:
// - ptr: Pointer to atomic storage.
// - value: Operand.
// - order: Memory ordering constraint.
template <typename T> void cmnAtomicXor(T* ptr, T value, CmnMemoryOrder order = CMN_SEQ_CST);

// Issues an atomic thread fence.
//
// Inputs:
// - order: Memory ordering constraint.
template <typename T> void cmnAtomicFence(CmnMemoryOrder order);

#include "atomic_gnu.inc"

#endif // CMN_ATOMIC_H

