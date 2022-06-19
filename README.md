nim-serialization
=================

[![Build Status](https://travis-ci.org/status-im/nim-serialization.svg?branch=master)](https://travis-ci.org/status-im/nim-serialization)
[![Build status](https://ci.appveyor.com/api/projects/status/muejuk735c11brjd/branch/master?svg=true)](https://ci.appveyor.com/project/nimbus/nim-serialization/branch/master)
[![License: Apache](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
![Github action](https://github.com/status-im/nim-serialization/workflows/CI/badge.svg)

## Introduction

The `serialization` package aims to provide a common generic and efficient
interface for marshaling Nim values to and from various serialized formats.
Individual formats are implemented in separated packages such as
[`json_serialization`](https://github.com/status-im/nim-json-serialization)
while this package provides the common interfaces shared between all of them
and the means to customize your Nim types for the purposes of serialization.

The internal mechanisms of the library allow for implementing the required
marshaling logic in highly efficient way that goes from bytes to Nim values
and vice versa without allocating any intermediate structures.

## Defining serialization formats

A serialization format is implemented through defining a `Reader` and `Writer`
type for the format and then by providing the following type declaration:

```nim
serializationFormat Json,                         # This is the name of the format.
                                                  # Most APIs provided by the library will accept
                                                  # this identifier as a required parameter.
                    mimeType = "application/json" # Mime type associated with the format (Optional).

Json.setReader JsonReader                         # The associated Reader type.
Json.setWriter JsonWriter,                        # The associated Writer type.
               PreferredOutput = string           # APIs such as `Json.encode` will return this type.
```

## Common API

Most of the time, you'll be using the following high-level APIs when encoding
and decoding values:

#### `Format.encode(value: auto, params: varargs): Format.PreferredOutput`

Encodes a value in the specified format returning the preferred output type
for the format (usually `string` or `seq[byte]`). All extra params will be
forwarded without modification to the constructor of the used `Writer` type.

Example:

```nim
assert Json.encode(@[1, 2, 3], pretty = false) == "[1, 2, 3]"
```

#### `Format.decode(input: openArray[byte]|string, RecordType: type, params: varargs): RecordType`

Decodes and returns a value of the specified `RecordType`. All params will
be forwarded without modification to the used `Reader` type. A Format-specific
descendant of `SerializationError` may be thrown in case of error.

#### `Format.saveFile(filename: string, value: auto, params: varargs)`

Similar to `encode`, but saves the result in a file.

#### `Format.loadFile(filename: string, RecordType: type, params: varargs): RecordType`

Similar to `decode`, but treats the contents of a file as an input.

#### `reader.readValue(RecordType: type): RecordType`

Reads a single value of the designated type from the stream associated with a
particular reader.

#### `writer.writeValue(value: auto)`

Encodes a single value and writes it to the output stream of a particular writer.

### Custom serialization of user-defined types

By default, record types will have all of their fields serialized. You can
alter this behavior by attaching the `dontSerialize` pragma to exclude fields.
The pragma `serializedFieldName(name: string)` can be used to modify the name
of the field in formats such as Json and XML.

Alternatively, if you are not able to modify the definition of a particular
Nim type, you can use the `setSerializedFields` macro to achieve the same
in a less intrusive way.

The following two definitions can be considered equivalent:

```nim
type
  Foo = object
    a: string
    b {.dontSerialize.}: int

setSerializedFields Foo:
  a
```

As you can see, `setSerializedFields` accepts a block where each serialized
field is listed on a separate line.

#### `customSerialization(RecordType: type, spec)`




#### `totalSerializedFields(RecordType: type)`

Returns the number of serialized fields in the specified format.

### Implementing Readers

### Implementing Writers

## Contributing

When submitting pull requests, please add test cases for any new features
or fixes and make sure `nimble test` is still able to execute the entire
test suite successfully.

[BOUNTIES]: https://github.com/status-im/nim-confutils/issues?q=is%3Aissue+is%3Aopen+label%3Abounty

## License

Licensed and distributed under either of

* MIT license: [LICENSE-MIT](LICENSE-MIT) or http://opensource.org/licenses/MIT

or

* Apache License, Version 2.0, ([LICENSE-APACHEv2](LICENSE-APACHEv2) or http://www.apache.org/licenses/LICENSE-2.0)

at your option. These files may not be copied, modified, or distributed except according to those terms.

