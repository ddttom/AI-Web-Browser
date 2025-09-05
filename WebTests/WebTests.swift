import Testing
@testable import Web

struct WebTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }
    
    @Test func testPerformanceOptimizations() async throws {
        // Test that MLXModelService singleton is working
        let service1 = MLXModelService.shared
        let service2 = MLXModelService.shared
        #expect(service1 === service2, "MLXModelService should be a singleton")
        
        // Test that AIAssistant singleton is working
        await MainActor.run {
            let assistant1 = AIAssistant.shared
            let assistant2 = AIAssistant.shared
            #expect(assistant1 === assistant2, "AIAssistant should be a singleton")
        }
    }

}
