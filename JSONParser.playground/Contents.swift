import UIKit

// MARK: - Result

enum Result<E, A> {
    case success(A)
    case error(E)
}

extension Result {
    func map<B>(_ f: (A) -> B) -> Result<E, B> {
        switch self {
        case let .success(x): return .success(f(x))
        case let .error(e): return .error(e)
        }
    }
}

extension Result {
    func flatMap<B>(_ f: (A) -> Result<E, B>) -> Result<E, B> {
        switch self {
        case let .success(x): return f(x)
        case let .error(e): return .error(e)
        }
    }
}

extension Result {
    init(pure value: A) {
        self = .success(value)
    }
}

// MARK: - Applicative

precedencegroup Applicative {
    associativity: left
}
infix operator <*>: Applicative

// MARK: - Semigroup

infix operator <>: AdditionPrecedence

protocol Semigroup {
    static func <> (lhs: Self, rhs: Self) -> Self
}

extension Array: Semigroup {
    static func <> (lhs: Array, rhs: Array) -> Array {
        return lhs + rhs
    }
}

func <*> <E: Semigroup, A, B>(f: Result<E, (A) -> B>, x: Result<E, A>) -> Result<E, B> {
    switch (f, x) {
    case let (.success(f), _): return x.map(f)
    case let (.error(e), .success): return .error(e)
    case let (.error(e1), .error(e2)): return .error(e1 <> e2)
    }
}

// MARK: - Library - Any Value Parsing Generic

struct Value<A> {
    let description: String
    let parse: (Any) -> A?
    
    func check(description: String, condition: @escaping (A) -> Bool) -> Value<A> {
        let combined = "\(self.description), \(description)"
        return Value(description: combined, parse: { (value) -> A? in
            return self.parse(value).flatMap { condition($0) ? $0 : nil }
        })
    }
    
    func map<B>(description: String, f: @escaping (A) -> B) -> Value<B> {
        let combined = "\(self.description) -> \(description)"
        return Value<B>(description: combined, parse: { any in
            return self.parse(any).map(f)
        })
    }
    
    func flatMap<B>(description: String, f: @escaping (A) -> B) -> Value<B> {
        let combined = "\(self.description) -> \(description)"
        return Value<B>(description: combined) { any in
            return self.parse(any).flatMap { a in f(a) }
        }
    }
}

// MARK: - Library - JSON Parsing Generic

typealias JSON = [String: Any]

struct KeyedValue<A> {
    let description: String
    let key: String
    let parse: (JSON) -> Result<[String], A>
}

extension KeyedValue {
    init(description: String, key: String, value: Value<A>) {
        let fullDescription = "\(description) - \(value.description)"
        self.description = fullDescription
        self.key = key
        self.parse = { json in
            guard let v = json[key] else { return .error(["missing \(key) (\(fullDescription))"]) }
            return value.parse(v).map(Result<[String], A>.success) ?? .error(["invalid \(key) (\(fullDescription))"])
        }
    }
    
    var optional: KeyedValue<A?> {
        return KeyedValue<A?>(description: "\(self.description) (optional)", key: self.key, parse: { (json) in
            guard json[self.key] != nil else { return .success(nil) }
            return self.parse(json).map(Optional.some)
        })
    }
    
    func map<B>(description: String, f: @escaping (A) -> B) -> KeyedValue<B> {
        let combined = "\(self.description) -> \(description)"
        return KeyedValue<B>(description: combined, key: key, parse: { any in
            return self.parse(any).map(f)
        })
    }
    
    func flatMap<B>(description: String, f: @escaping (A) -> Result<[String], B>) -> KeyedValue<B> {
        let combined = "\(self.description) -> \(description)"
        return KeyedValue<B>(description: combined, key: key, parse: { any in
            return self.parse(any).flatMap(f)
        })
    }
}

struct Parser<A> {
    let descriptions: [String: String]
    let parse: (JSON) -> Result<[String], A>
}

extension Parser {
    init(_ p: KeyedValue<A>) {
        self.descriptions = [p.key: p.description]
        self.parse = p.parse
    }
    
    init(pure value: A) {
        self.descriptions = [:]
        self.parse = { _ in .success(value) }
    }
}

func <*> <A, B>(lhs: Parser<(A) -> B>, rhs: KeyedValue<A>) -> Parser<B> {
    var descriptions = lhs.descriptions
    descriptions[rhs.key] = rhs.description
    return Parser(descriptions: descriptions, parse: { (json) in
        switch (lhs.parse(json), rhs.parse(json)) {
        case let (.success(f), .success(a)): return .success(f(a))
        case let (.success, .error(e)): return .error(e)
        case let (.error(e), .success): return .error(e)
        case let (.error(e1), .error(e2)): return .error(e1 <> e2)
        }
    })
}

// MARK: - Library - JSON Parsing Primitive Types

let string = Value<String>(description: "string", parse: { $0 as? String })
let int = Value<Int>(description: "int", parse: { $0 as? Int })
let float = Value<Float>(description: "float", parse: { $0 as? Float })
let json = Value<JSON>(description: "json", parse: { $0 as? JSON })
let jsonArray = Value<[JSON]>(description: "json array", parse: { $0 as? [JSON] })


// MARK: - App - Logic Below

// MARK: - Custom value types

let dateFormatter = DateFormatter()
dateFormatter.dateFormat = "dd-MM-yyyy"
let date = Value<Date>(description: "date", parse: { ($0 as? String).flatMap(dateFormatter.date) })

// MARK: - Model

struct Food {
    var name: String
}

struct User {
    var id: Int
    var email: String
    var city: String?
    var dob: Date
    var food: Food
    var otherFoods: [Food]?
}

// MARK: - Parsing

extension Food {
    static let create = { name in Food(name: name) }
    static let parse = parser.parse
    static let spec = parser.descriptions
    
    private static let parser: Parser<Food> = Parser(pure: create) <*> _name
    private static let _name = KeyedValue(description: "Food name", key: "name", value: string)
}

extension User {
    static let create = { id in { email in { city in { dob in { food in { otherFoods in User(id: id, email: email, city: city, dob: dob, food: food, otherFoods: otherFoods) } } } } } }
    static let parse = parser.parse
    static let spec = parser.descriptions
    
    private static let parser: Parser<User> = Parser(pure: create) <*> _id <*> _email <*> _city <*> _dob <*> _food <*> _fallback
    private static let _id = KeyedValue(description: "The id", key: "id", value: int.check(description: "non-zero", condition: { $0 > 0 }))
    private static let _email = KeyedValue(description: "The email address", key: "email", value: string)
    private static let _city = KeyedValue(description: "The city", key: "city", value: string).optional
    private static let _dob = KeyedValue(description: "The date of birth", key: "dob", value: date)
    private static let _food = KeyedValue(description: "The favourite food", key: "food", value: json)
        .flatMap(description: " - json") { value in
            return Food.parse(value)
        }
    private static let _fallback = KeyedValue(description: "Fallback foods", key: "fallback", value: jsonArray)
        .flatMap(description: " - array") { values -> Result<[String], [Food]> in
            let foods = values.map { value in
                return Food.parse(value)
            }
            return foods.reduce(Result<[String], [Food]>(pure: []), { (lhs, rhs) -> Result<[String], [Food]> in
                switch (lhs, rhs) {
                case let (.success(a), .success(b)): return .success(a <> [b])
                case let (.success, .error(e)): return .error(e)
                case let (.error(e), .success): return .error(e)
                case let (.error(e1), .error(e2)): return .error(e1 <> e2)
                }
            })
        }.optional
}

// MARK: - Results

print("SPECIFICATION")
dump(User.spec)

print("\n\n")
dump(User.parse([:]))
print("\n\n")
dump(User.parse(["id": 1]))
print("\n\n")
dump(User.parse(["id": 2, "email": "user1@test.com"]))
print("\n\n")
dump(User.parse(["id": 3, "email": "user2@test.com", "dob": "21-07-1987"]))
print("\n\n")
dump(User.parse(["id": 4, "email": 1, "city": "London", "dob": "21-07-1987"]))
print("\n\n")
dump(User.parse(["id": 5, "city": 1, "dob": "21-07-1987"]))
print("\n\n")
dump(User.parse(["id": 6, "email": "user3@test.com", "city": "London", "dob": "21-07-1987"]))
print("\n\n")
dump(User.parse(["id": 6, "email": "user3@test.com", "city": "London", "dob": "21-07-1987", "food": ["name": 1]]))
print("\n\n")
dump(User.parse(["id": 6, "email": "user3@test.com", "city": "London", "dob": "21-07-1987", "food": ["namez": "pizza"]]))
print("\n\n")
dump(User.parse(["id": 6, "email": "user3@test.com", "city": "London", "dob": "21-07-1987", "food": ["name": "pizza"]]))
print("\n\n")
dump(User.parse(["id": 6, "email": "user3@test.com", "city": "London", "dob": "21-07-1987", "food": ["name": "pizza"], "fallback": "string"]))
print("\n\n")
dump(User.parse(["id": 6, "email": "user3@test.com", "city": "London", "dob": "21-07-1987", "food": ["name": "pizza"]]))
print("\n\n")
dump(User.parse(["id": 6, "email": "user3@test.com", "city": "London", "dob": "21-07-1987", "food": ["name": "pizza"], "fallback": [["name": "burgers"], ["name": "sushi"]]]))
