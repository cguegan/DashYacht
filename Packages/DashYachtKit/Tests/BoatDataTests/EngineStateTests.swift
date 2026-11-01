import Testing
import SignalK
import BoatData

struct EngineStateTests {
    @Test("Astern shows below zero, so the helmsman sees at once that the engine pulls backwards")
    func astern() throws {
        let engine = try #require(EngineState(revolutions: .number(20), gear: .string("Reverse")))
        #expect(engine.rpm == 1200)
        #expect(engine.signedRPM == -1200)
        #expect(engine.text == "1200 R")
    }

    @Test("In neutral the engine turns but does not drive: no bar, RPM still in the text")
    func neutral() throws {
        let engine = try #require(EngineState(revolutions: .number(12.5), gear: .string("Neutral")))
        #expect(engine.signedRPM == 0)
        #expect(engine.text == "750 N")
    }

    @Test("Without gear data the direction is unknown: ahead, and the text does not claim a gear")
    func noGear() throws {
        let engine = try #require(EngineState(revolutions: .number(25), gear: nil))
        #expect(engine.signedRPM == 1500)
        #expect(engine.text == "1500")
    }

    @Test("No revolutions means no engine value, even when the gear is known")
    func noRevolutions() {
        #expect(EngineState(revolutions: nil, gear: .string("Forward")) == nil)
    }
}
