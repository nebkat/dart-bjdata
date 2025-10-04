/// Error thrown by BJData serialization if an object cannot be serialized.
///
/// The [unsupportedObject] field holds that object that failed to be serialized.
///
/// If an object isn't directly serializable, the serializer calls the `toBjdata`
/// method on the object. If that call fails, the error will be stored in the
/// [cause] field. If the call returns an object that isn't directly
/// serializable, the [cause] is null.
class BjdataUnsupportedObjectError extends Error {
  /// The object that could not be serialized.
  final Object? unsupportedObject;

  /// The exception thrown when trying to convert the object.
  final Object? cause;

  /// The partial result of the conversion, up until the error happened.
  ///
  /// May be null.
  final Object? partialResult;

  BjdataUnsupportedObjectError(
    this.unsupportedObject, {
    this.cause,
    this.partialResult,
  });

  @override
  String toString() {
    var safeString = Error.safeToString(unsupportedObject);
    String prefix;
    if (cause != null) {
      prefix = "Converting object to an encodable object failed:";
    } else {
      prefix = "Converting object did not return an encodable object:";
    }
    return "$prefix $safeString";
  }
}

/// Reports that an object could not be stringified due to cyclic references.
///
/// An object that references itself cannot be serialized by
/// [BjdataCodec.encode]/[BjdataEncoder.convert].
/// When the cycle is detected, a [BjdataCyclicError] is thrown.
class BjdataCyclicError extends BjdataUnsupportedObjectError {
  /// The first object that was detected as part of a cycle.
  BjdataCyclicError(super.object);

  @override
  String toString() => "Cyclic error in BJData stringify";
}
