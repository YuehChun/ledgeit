import Testing
@testable import LedgeIt

struct JSONParserTests {

    // MARK: - Direct Parse

    struct SimpleModel: Codable, Equatable {
        let name: String
        let value: Int
    }

    @Test func directParse() {
        let json = #"{"name":"test","value":42}"#
        let result = JSONParser.parse(json, as: SimpleModel.self)
        #expect(result == SimpleModel(name: "test", value: 42))
    }

    // MARK: - Code Block Extraction

    @Test func parseFromMarkdownCodeBlock() {
        let text = """
        Here is the result:
        ```json
        {"name":"from_block","value":7}
        ```
        """
        let result = JSONParser.parse(text, as: SimpleModel.self)
        #expect(result == SimpleModel(name: "from_block", value: 7))
    }

    @Test func parseFromCodeBlockWithoutLanguage() {
        let text = """
        ```
        {"name":"no_lang","value":3}
        ```
        """
        let result = JSONParser.parse(text, as: SimpleModel.self)
        #expect(result == SimpleModel(name: "no_lang", value: 3))
    }

    // MARK: - JSON Block Extraction

    @Test func extractJSONFromSurroundingText() {
        let text = #"The answer is {"name":"embedded","value":99} and that's it."#
        let result = JSONParser.parse(text, as: SimpleModel.self)
        #expect(result == SimpleModel(name: "embedded", value: 99))
    }

    // MARK: - Fix Common Issues

    @Test func trailingComma() {
        let json = #"{"name":"trailing","value":1,}"#
        let result = JSONParser.parse(json, as: SimpleModel.self)
        #expect(result == SimpleModel(name: "trailing", value: 1))
    }

    @Test func singleQuotes() {
        let json = "{'name':'single','value':5}"
        let result = JSONParser.parse(json, as: SimpleModel.self)
        #expect(result == SimpleModel(name: "single", value: 5))
    }

    @Test func comments() {
        let json = """
        {
            "name": "commented", // this is a comment
            "value": 8
        }
        """
        let result = JSONParser.parse(json, as: SimpleModel.self)
        #expect(result == SimpleModel(name: "commented", value: 8))
    }

    // MARK: - Array Parse

    @Test func parseArray() {
        let json = #"[{"name":"a","value":1},{"name":"b","value":2}]"#
        let result = JSONParser.parse(json, as: [SimpleModel].self)
        #expect(result?.count == 2)
        #expect(result?[0].name == "a")
        #expect(result?[1].name == "b")
    }

    // MARK: - Dict Parse

    @Test func parseDict() {
        let json = #"{"key":"value","num":42}"#
        let result = JSONParser.parseDict(json)
        #expect(result?["key"] as? String == "value")
        #expect(result?["num"] as? Int == 42)
    }

    @Test func parseDictFromCodeBlock() {
        let text = """
        ```json
        {"extracted":true}
        ```
        """
        let result = JSONParser.parseDict(text)
        #expect(result?["extracted"] as? Bool == true)
    }

    // MARK: - Edge Cases

    @Test func invalidJSON() {
        let result = JSONParser.parse("not json at all", as: SimpleModel.self)
        #expect(result == nil)
    }

    @Test func emptyString() {
        let result = JSONParser.parse("", as: SimpleModel.self)
        #expect(result == nil)
    }

    @Test func nestedJSON() {
        struct Nested: Codable, Equatable {
            let outer: String
            let inner: SimpleModel
        }
        let json = #"{"outer":"hello","inner":{"name":"nested","value":10}}"#
        let result = JSONParser.parse(json, as: Nested.self)
        #expect(result?.outer == "hello")
        #expect(result?.inner.name == "nested")
    }
}
