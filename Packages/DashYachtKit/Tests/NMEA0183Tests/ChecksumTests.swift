import Testing
import NMEA0183

// Serial lines on boats pick up noise. A corrupted sentence that passes as valid
// shows a wrong position, depth or wind to the skipper, so the checksum must catch it.
struct ChecksumTests {
    @Test("Valid sentences from real devices are accepted", arguments: [
        "$GPRMC,123519,A,4807.038,N,01131.000,E,022.4,084.4,230394,003.1,W*6A",
        "$GPGGA,123519,4807.038,N,01131.000,E,1,08,0.9,545.4,M,46.9,M,,*47",
        "!AIVDM,1,1,,B,177KQJ5000G?tO`K>RA1wUbN0TKH,0*5C",
        "$GPRMC,123519,A,4807.038,N,01131.000,E,022.4,084.4,230394,003.1,W*6a\r\n",
    ])
    func acceptsValid(sentence: String) {
        #expect(Checksum.isValid(sentence))
    }

    @Test("One corrupted character is rejected")
    func rejectsCorruptedData() {
        // Speed over ground changed from 022.4 to 922.4 knots.
        #expect(!Checksum.isValid("$GPRMC,123519,A,4807.038,N,01131.000,E,922.4,084.4,230394,003.1,W*6A"))
    }

    @Test("Sentences that cannot be checked are rejected", arguments: [
        "$GPRMC,123519,A,4807.038,N,01131.000,E,022.4,084.4,230394,003.1,W",
        "$GPRMC,123519,A,4807.038,N,01131.000,E,022.4,084.4,230394,003.1,W*",
        "$GPRMC,123519,A,4807.038,N,01131.000,E,022.4,084.4,230394,003.1,W*ZZ",
        "GPRMC,123519,A,4807.038,N,01131.000,E,022.4,084.4,230394,003.1,W*6A",
        "",
    ])
    func rejectsUncheckable(sentence: String) {
        #expect(!Checksum.isValid(sentence))
    }
}
