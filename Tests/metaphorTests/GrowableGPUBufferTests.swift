import Testing
import Metal
import simd
@testable import MetaphorCore
import MetaphorTestSupport

@Suite("GrowableGPUBuffer", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct GrowableGPUBufferTests {

    @Test("init creates triple-buffered storage")
    func tripleBuffered() throws {
        let device = MetalTestHelper.device!
        let buf = try GrowableGPUBuffer<SIMD4<Float>>(device: device, initialCapacity: 128)
        #expect(buf.buffers.count == 3)
        #expect(buf.pointers.count == 3)
    }

    @Test("initial capacity matches parameter")
    func initialCapacity() throws {
        let device = MetalTestHelper.device!
        let buf = try GrowableGPUBuffer<Float>(device: device, initialCapacity: 256)
        #expect(buf.capacity == 256)
    }

    @Test("buffer(for:) wraps with modular index")
    func bufferModularIndex() throws {
        let device = MetalTestHelper.device!
        let buf = try GrowableGPUBuffer<Float>(device: device, initialCapacity: 64)
        // Index 0, 1, 2 should all return different buffers
        let b0 = buf.buffer(for: 0)
        let b1 = buf.buffer(for: 1)
        let b2 = buf.buffer(for: 2)
        // Index 3 wraps to 0
        let b3 = buf.buffer(for: 3)
        #expect(b0 === b3)
        #expect(b0 !== b1)
        #expect(b1 !== b2)
    }

    @Test("pointer(for:) wraps with modular index")
    func pointerModularIndex() throws {
        let device = MetalTestHelper.device!
        let buf = try GrowableGPUBuffer<Float>(device: device, initialCapacity: 64)
        let p0 = buf.pointer(for: 0)
        let p3 = buf.pointer(for: 3)
        #expect(p0 == p3)
    }

    @Test("ensureCapacity returns true when sufficient")
    func ensureCapacitySufficient() throws {
        let device = MetalTestHelper.device!
        let buf = try GrowableGPUBuffer<Float>(device: device, initialCapacity: 1024)
        let result = buf.ensureCapacity(512, activeIndex: 0, usedCount: 0)
        #expect(result == true)
        #expect(buf.capacity == 1024) // no growth
    }

    @Test("ensureCapacity grows when needed")
    func ensureCapacityGrows() throws {
        let device = MetalTestHelper.device!
        let buf = try GrowableGPUBuffer<Float>(device: device, initialCapacity: 128, maxCapacity: 10000)
        let result = buf.ensureCapacity(200, activeIndex: 0, usedCount: 0)
        #expect(result == true)
        #expect(buf.capacity >= 200)
    }

    @Test("growth doubles capacity")
    func growthDoubles() throws {
        let device = MetalTestHelper.device!
        let buf = try GrowableGPUBuffer<Float>(device: device, initialCapacity: 128, maxCapacity: 10000)
        _ = buf.ensureCapacity(129, activeIndex: 0, usedCount: 0)
        #expect(buf.capacity == 256) // doubled
    }

    @Test("maxCapacity blocks further growth")
    func maxCapacityBlock() throws {
        let device = MetalTestHelper.device!
        let buf = try GrowableGPUBuffer<Float>(device: device, initialCapacity: 128, maxCapacity: 200)
        let result = buf.ensureCapacity(300, activeIndex: 0, usedCount: 0)
        #expect(result == false)
    }

    @Test("data preserved after growth")
    func dataPreserved() throws {
        let device = MetalTestHelper.device!
        let buf = try GrowableGPUBuffer<Float>(device: device, initialCapacity: 64, maxCapacity: 10000)

        // Write some data to buffer 0
        let ptr = buf.pointer(for: 0)
        ptr[0] = 42.0
        ptr[1] = 99.0
        ptr[2] = -7.5

        // Grow (needs to copy usedCount=3 elements from active index 0)
        let result = buf.ensureCapacity(100, activeIndex: 0, usedCount: 3)
        #expect(result == true)
        #expect(buf.capacity >= 100)

        // Verify data was copied
        let newPtr = buf.pointer(for: 0)
        expectApproxEqual(newPtr[0], 42.0)
        expectApproxEqual(newPtr[1], 99.0)
        expectApproxEqual(newPtr[2], -7.5)
    }

    @Test("buffer labels are set")
    func bufferLabels() throws {
        let device = MetalTestHelper.device!
        let buf = try GrowableGPUBuffer<Float>(device: device, initialCapacity: 64, label: "test.buf")
        #expect(buf.buffer(for: 0).label == "test.buf.0")
        #expect(buf.buffer(for: 1).label == "test.buf.1")
        #expect(buf.buffer(for: 2).label == "test.buf.2")
    }
}
