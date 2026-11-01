import Testing
import SignalK
import BoatData

struct EngineStateTests {
    @Test("Astern shows below zero, so the helmsman sees at once that the engine pulls backwards")
    func astern() throws {
        let engine = try #require(EngineState(revolutions: .number(20), gear: .string("Reverse")))
        #expect(engine.rpm == 1200)
        #expect(engine.signedRPM == -1200)
        #expect(engine.text == "1\u{202F}200")
    }

    @Test("In neutral the engine turns but does not drive: no bar, but the RPM is still shown")
    func neutral() throws {
        let engine = try #require(EngineState(revolutions: .number(12.5), gear: .string("Neutral")))
        #expect(engine.signedRPM == 0)
        #expect(engine.text == "750")
    }

    @Test("Without gear data the direction is unknown: the bar goes ahead")
    func noGear() throws {
        let engine = try #require(EngineState(revolutions: .number(25), gear: nil))
        #expect(engine.signedRPM == 1500)
    }

    @Test("Thousands are set apart by a narrow space, and the hundreds keep their zeros")
    func thousands() throws {
        #expect(try #require(EngineState(revolutions: .number(1005.0 / 60), gear: nil)).text == "1\u{202F}005")
        #expect(try #require(EngineState(revolutions: .number(999.6 / 60), gear: nil)).text == "1\u{202F}000")
    }

    @Test("No revolutions means no engine value, even when the gear is known")
    func noRevolutions() {
        #expect(EngineState(revolutions: nil, gear: .string("Forward")) == nil)
    }
}
