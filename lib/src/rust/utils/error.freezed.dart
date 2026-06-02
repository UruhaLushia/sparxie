// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'error.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$MihomoError {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MihomoError);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'MihomoError()';
}


}

/// @nodoc
class $MihomoErrorCopyWith<$Res>  {
$MihomoErrorCopyWith(MihomoError _, $Res Function(MihomoError) __);
}


/// Adds pattern-matching-related methods to [MihomoError].
extension MihomoErrorPatterns on MihomoError {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( MihomoError_InvalidUrl value)?  invalidUrl,TResult Function( MihomoError_InvalidRegex value)?  invalidRegex,TResult Function( MihomoError_Upstream value)?  upstream,TResult Function( MihomoError_Network value)?  network,TResult Function( MihomoError_InvalidJson value)?  invalidJson,TResult Function( MihomoError_Other value)?  other,required TResult orElse(),}){
final _that = this;
switch (_that) {
case MihomoError_InvalidUrl() when invalidUrl != null:
return invalidUrl(_that);case MihomoError_InvalidRegex() when invalidRegex != null:
return invalidRegex(_that);case MihomoError_Upstream() when upstream != null:
return upstream(_that);case MihomoError_Network() when network != null:
return network(_that);case MihomoError_InvalidJson() when invalidJson != null:
return invalidJson(_that);case MihomoError_Other() when other != null:
return other(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( MihomoError_InvalidUrl value)  invalidUrl,required TResult Function( MihomoError_InvalidRegex value)  invalidRegex,required TResult Function( MihomoError_Upstream value)  upstream,required TResult Function( MihomoError_Network value)  network,required TResult Function( MihomoError_InvalidJson value)  invalidJson,required TResult Function( MihomoError_Other value)  other,}){
final _that = this;
switch (_that) {
case MihomoError_InvalidUrl():
return invalidUrl(_that);case MihomoError_InvalidRegex():
return invalidRegex(_that);case MihomoError_Upstream():
return upstream(_that);case MihomoError_Network():
return network(_that);case MihomoError_InvalidJson():
return invalidJson(_that);case MihomoError_Other():
return other(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( MihomoError_InvalidUrl value)?  invalidUrl,TResult? Function( MihomoError_InvalidRegex value)?  invalidRegex,TResult? Function( MihomoError_Upstream value)?  upstream,TResult? Function( MihomoError_Network value)?  network,TResult? Function( MihomoError_InvalidJson value)?  invalidJson,TResult? Function( MihomoError_Other value)?  other,}){
final _that = this;
switch (_that) {
case MihomoError_InvalidUrl() when invalidUrl != null:
return invalidUrl(_that);case MihomoError_InvalidRegex() when invalidRegex != null:
return invalidRegex(_that);case MihomoError_Upstream() when upstream != null:
return upstream(_that);case MihomoError_Network() when network != null:
return network(_that);case MihomoError_InvalidJson() when invalidJson != null:
return invalidJson(_that);case MihomoError_Other() when other != null:
return other(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String field0)?  invalidUrl,TResult Function( String pattern,  String message)?  invalidRegex,TResult Function( int status,  String body)?  upstream,TResult Function( String field0)?  network,TResult Function( String field0)?  invalidJson,TResult Function( String field0)?  other,required TResult orElse(),}) {final _that = this;
switch (_that) {
case MihomoError_InvalidUrl() when invalidUrl != null:
return invalidUrl(_that.field0);case MihomoError_InvalidRegex() when invalidRegex != null:
return invalidRegex(_that.pattern,_that.message);case MihomoError_Upstream() when upstream != null:
return upstream(_that.status,_that.body);case MihomoError_Network() when network != null:
return network(_that.field0);case MihomoError_InvalidJson() when invalidJson != null:
return invalidJson(_that.field0);case MihomoError_Other() when other != null:
return other(_that.field0);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String field0)  invalidUrl,required TResult Function( String pattern,  String message)  invalidRegex,required TResult Function( int status,  String body)  upstream,required TResult Function( String field0)  network,required TResult Function( String field0)  invalidJson,required TResult Function( String field0)  other,}) {final _that = this;
switch (_that) {
case MihomoError_InvalidUrl():
return invalidUrl(_that.field0);case MihomoError_InvalidRegex():
return invalidRegex(_that.pattern,_that.message);case MihomoError_Upstream():
return upstream(_that.status,_that.body);case MihomoError_Network():
return network(_that.field0);case MihomoError_InvalidJson():
return invalidJson(_that.field0);case MihomoError_Other():
return other(_that.field0);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String field0)?  invalidUrl,TResult? Function( String pattern,  String message)?  invalidRegex,TResult? Function( int status,  String body)?  upstream,TResult? Function( String field0)?  network,TResult? Function( String field0)?  invalidJson,TResult? Function( String field0)?  other,}) {final _that = this;
switch (_that) {
case MihomoError_InvalidUrl() when invalidUrl != null:
return invalidUrl(_that.field0);case MihomoError_InvalidRegex() when invalidRegex != null:
return invalidRegex(_that.pattern,_that.message);case MihomoError_Upstream() when upstream != null:
return upstream(_that.status,_that.body);case MihomoError_Network() when network != null:
return network(_that.field0);case MihomoError_InvalidJson() when invalidJson != null:
return invalidJson(_that.field0);case MihomoError_Other() when other != null:
return other(_that.field0);case _:
  return null;

}
}

}

/// @nodoc


class MihomoError_InvalidUrl extends MihomoError {
  const MihomoError_InvalidUrl(this.field0): super._();
  

 final  String field0;

/// Create a copy of MihomoError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MihomoError_InvalidUrlCopyWith<MihomoError_InvalidUrl> get copyWith => _$MihomoError_InvalidUrlCopyWithImpl<MihomoError_InvalidUrl>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MihomoError_InvalidUrl&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'MihomoError.invalidUrl(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $MihomoError_InvalidUrlCopyWith<$Res> implements $MihomoErrorCopyWith<$Res> {
  factory $MihomoError_InvalidUrlCopyWith(MihomoError_InvalidUrl value, $Res Function(MihomoError_InvalidUrl) _then) = _$MihomoError_InvalidUrlCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$MihomoError_InvalidUrlCopyWithImpl<$Res>
    implements $MihomoError_InvalidUrlCopyWith<$Res> {
  _$MihomoError_InvalidUrlCopyWithImpl(this._self, this._then);

  final MihomoError_InvalidUrl _self;
  final $Res Function(MihomoError_InvalidUrl) _then;

/// Create a copy of MihomoError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(MihomoError_InvalidUrl(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class MihomoError_InvalidRegex extends MihomoError {
  const MihomoError_InvalidRegex({required this.pattern, required this.message}): super._();
  

 final  String pattern;
 final  String message;

/// Create a copy of MihomoError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MihomoError_InvalidRegexCopyWith<MihomoError_InvalidRegex> get copyWith => _$MihomoError_InvalidRegexCopyWithImpl<MihomoError_InvalidRegex>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MihomoError_InvalidRegex&&(identical(other.pattern, pattern) || other.pattern == pattern)&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode => Object.hash(runtimeType,pattern,message);

@override
String toString() {
  return 'MihomoError.invalidRegex(pattern: $pattern, message: $message)';
}


}

/// @nodoc
abstract mixin class $MihomoError_InvalidRegexCopyWith<$Res> implements $MihomoErrorCopyWith<$Res> {
  factory $MihomoError_InvalidRegexCopyWith(MihomoError_InvalidRegex value, $Res Function(MihomoError_InvalidRegex) _then) = _$MihomoError_InvalidRegexCopyWithImpl;
@useResult
$Res call({
 String pattern, String message
});




}
/// @nodoc
class _$MihomoError_InvalidRegexCopyWithImpl<$Res>
    implements $MihomoError_InvalidRegexCopyWith<$Res> {
  _$MihomoError_InvalidRegexCopyWithImpl(this._self, this._then);

  final MihomoError_InvalidRegex _self;
  final $Res Function(MihomoError_InvalidRegex) _then;

/// Create a copy of MihomoError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? pattern = null,Object? message = null,}) {
  return _then(MihomoError_InvalidRegex(
pattern: null == pattern ? _self.pattern : pattern // ignore: cast_nullable_to_non_nullable
as String,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class MihomoError_Upstream extends MihomoError {
  const MihomoError_Upstream({required this.status, required this.body}): super._();
  

 final  int status;
 final  String body;

/// Create a copy of MihomoError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MihomoError_UpstreamCopyWith<MihomoError_Upstream> get copyWith => _$MihomoError_UpstreamCopyWithImpl<MihomoError_Upstream>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MihomoError_Upstream&&(identical(other.status, status) || other.status == status)&&(identical(other.body, body) || other.body == body));
}


@override
int get hashCode => Object.hash(runtimeType,status,body);

@override
String toString() {
  return 'MihomoError.upstream(status: $status, body: $body)';
}


}

/// @nodoc
abstract mixin class $MihomoError_UpstreamCopyWith<$Res> implements $MihomoErrorCopyWith<$Res> {
  factory $MihomoError_UpstreamCopyWith(MihomoError_Upstream value, $Res Function(MihomoError_Upstream) _then) = _$MihomoError_UpstreamCopyWithImpl;
@useResult
$Res call({
 int status, String body
});




}
/// @nodoc
class _$MihomoError_UpstreamCopyWithImpl<$Res>
    implements $MihomoError_UpstreamCopyWith<$Res> {
  _$MihomoError_UpstreamCopyWithImpl(this._self, this._then);

  final MihomoError_Upstream _self;
  final $Res Function(MihomoError_Upstream) _then;

/// Create a copy of MihomoError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? status = null,Object? body = null,}) {
  return _then(MihomoError_Upstream(
status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as int,body: null == body ? _self.body : body // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class MihomoError_Network extends MihomoError {
  const MihomoError_Network(this.field0): super._();
  

 final  String field0;

/// Create a copy of MihomoError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MihomoError_NetworkCopyWith<MihomoError_Network> get copyWith => _$MihomoError_NetworkCopyWithImpl<MihomoError_Network>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MihomoError_Network&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'MihomoError.network(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $MihomoError_NetworkCopyWith<$Res> implements $MihomoErrorCopyWith<$Res> {
  factory $MihomoError_NetworkCopyWith(MihomoError_Network value, $Res Function(MihomoError_Network) _then) = _$MihomoError_NetworkCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$MihomoError_NetworkCopyWithImpl<$Res>
    implements $MihomoError_NetworkCopyWith<$Res> {
  _$MihomoError_NetworkCopyWithImpl(this._self, this._then);

  final MihomoError_Network _self;
  final $Res Function(MihomoError_Network) _then;

/// Create a copy of MihomoError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(MihomoError_Network(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class MihomoError_InvalidJson extends MihomoError {
  const MihomoError_InvalidJson(this.field0): super._();
  

 final  String field0;

/// Create a copy of MihomoError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MihomoError_InvalidJsonCopyWith<MihomoError_InvalidJson> get copyWith => _$MihomoError_InvalidJsonCopyWithImpl<MihomoError_InvalidJson>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MihomoError_InvalidJson&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'MihomoError.invalidJson(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $MihomoError_InvalidJsonCopyWith<$Res> implements $MihomoErrorCopyWith<$Res> {
  factory $MihomoError_InvalidJsonCopyWith(MihomoError_InvalidJson value, $Res Function(MihomoError_InvalidJson) _then) = _$MihomoError_InvalidJsonCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$MihomoError_InvalidJsonCopyWithImpl<$Res>
    implements $MihomoError_InvalidJsonCopyWith<$Res> {
  _$MihomoError_InvalidJsonCopyWithImpl(this._self, this._then);

  final MihomoError_InvalidJson _self;
  final $Res Function(MihomoError_InvalidJson) _then;

/// Create a copy of MihomoError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(MihomoError_InvalidJson(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class MihomoError_Other extends MihomoError {
  const MihomoError_Other(this.field0): super._();
  

 final  String field0;

/// Create a copy of MihomoError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MihomoError_OtherCopyWith<MihomoError_Other> get copyWith => _$MihomoError_OtherCopyWithImpl<MihomoError_Other>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MihomoError_Other&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'MihomoError.other(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $MihomoError_OtherCopyWith<$Res> implements $MihomoErrorCopyWith<$Res> {
  factory $MihomoError_OtherCopyWith(MihomoError_Other value, $Res Function(MihomoError_Other) _then) = _$MihomoError_OtherCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$MihomoError_OtherCopyWithImpl<$Res>
    implements $MihomoError_OtherCopyWith<$Res> {
  _$MihomoError_OtherCopyWithImpl(this._self, this._then);

  final MihomoError_Other _self;
  final $Res Function(MihomoError_Other) _then;

/// Create a copy of MihomoError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(MihomoError_Other(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
