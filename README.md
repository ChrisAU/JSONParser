# JSONParser
Example of applicative JSON parsing

## Why?
This example actually allows us to generate a spec from our data and easily see when things change in the API. 

It also allows us to add validation while we are parsing to avoid creating any objects that we know will fail the next step (validation).

For example, a typical parser will generally use `Codable`. You may have an object like this (which is from this example):

```
struct User: Codable {
  enum CodingKeys: CodingKey, String {
    case id = "identifier"
    case email = "E-mail"
    case city = "location"
    case food = "favouriteFood"
    case fallback = "fallbackFoodsList"
  }

  var id: Int
  var email: String
  var city: String?
  var food: Food
  var fallback: [Food]  // In case your favourite food is unavailable...
}

struct Food: Codable {
  var name: String
}
```

You typically need to define `CodingKeys` (as seen above) if the API spec differs to your naming, this is just a naive example where everything lines up.

This doesn't handle non-codable types off the bat though, so if you want to parse a Date with some specific format you will need to re-implement the decode/encode methods.

This is powerful, we create an object if it matches this spec and throw an error otherwise, however, it doesn't allow us to throw more than one error without writing some custom logic.

What if multiple values in our API change? It's a single error, so we can only find out about errors singularly.

This is where this parsing 'exercise' starts to show it's value. 

You can return an array of errors that occurred during parsing to find out the whole picture, and fix everything in one go.

You can also print the spec as it last was, and send that over to your backend engineers to show them what you were expecting versus what you received.

Here is an example of the dump from this example:

```
SPECIFICATION
▿ 6 key/value pairs
  ▿ (2 elements)
    - key: "city"
    - value: "The city - string (optional)"
  ▿ (2 elements)
    - key: "fallback"
    - value: "Fallback foods - json array -> food array (optional)"
  ▿ (2 elements)
    - key: "dob"
    - value: "The date of birth - date"
  ▿ (2 elements)
    - key: "email"
    - value: "The email address - string"
  ▿ (2 elements)
    - key: "id"
    - value: "The id - int, non-zero"
  ▿ (2 elements)
    - key: "food"
    - value: "The favourite food - json -> food"
```

Pretty simple, it tells us things like the data type we are expecting and the types we are mapping them to (food array, food, optional) as well as any rules we have applied (non-zero).

## How?

Each type will need to define it's rules, descriptions, and mappers if the type needs to return a different value from what is in the JSON.

This could probably be cleaned up with some more generic functions; however, for this POC I felt like this sufficed.

```
extension User: Parseable {
    static let create = { id in { email in { city in { dob in { food in { otherFoods in User(id: id, email: email, city: city, dob: dob, food: food, otherFoods: otherFoods) } } } } } }
    static let parse = parser.parse
    static let spec = parser.descriptions
    
    private static let parser: Parser<User> = Parser(pure: create) <*> _id <*> _email <*> _city <*> _dob <*> _food <*> _fallback
    private static let _id = KeyedValue(description: "The id", key: "id", value: int.check(description: "non-zero", condition: { $0 > 0 }))
    private static let _email = KeyedValue(description: "The email address", key: "email", value: string)
    private static let _city = KeyedValue(description: "The city", key: "city", value: string).optional
    private static let _dob = KeyedValue(description: "The date of birth", key: "dob", value: date)
    private static let _food: KeyedValue<Food> = KeyedValue(description: "The favourite food", key: "food", value: json).tryParse()
    private static let _fallback: KeyedValue<[Food]?> = KeyedValue(description: "Fallback foods", key: "fallback", value: jsonArray).tryParse().optional
}
```

Our 'parser' variable is where the magic happens, and our 'User.parse' function is how we execute it's internal function.

Once we start noticing similar types we can define them at a more global level and reuse where necessary, `id` for example is a pretty common `KeyedValue` which will probably have the same rules in most cases.
