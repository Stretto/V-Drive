module vdrive.util.util;

import erupted.types;
import std.container.array;





/// check bool condition
void vkAssert(
	bool			assert_value,
	const( char )*	message = null,
	string			file = __FILE__,
	size_t			line = __LINE__,
	string			func = __FUNCTION__,
	const( char )*	msg_end = null
	) nothrow @nogc {
	// Todo(pp): print to stderr
	// Todo(pp): print to custom logger
	if( !assert_value ) {
		import core.stdc.stdio : printf;
		printf( "\n! ERROR !\n==============\n" );
		printHelper( message, file, line, func, msg_end );
	}
	assert( assert_value );
}


/// check the correctness of a vulkan result
void vkAssert(
	VkResult	vkResult, 
	string		file = __FILE__,
	size_t		line = __LINE__,
	string		func = __FUNCTION__,
	) nothrow @nogc {
	// Todo(pp): print to stderr
	// Todo(pp): print to custom logger
	vkResult.vkAssert( null, file, line, func );
}

/// check the correctness of a vulkan result with additinal message(s)
void vkAssert(
	VkResult		vkResult, 
	const( char )*	message,
	string			file = __FILE__,
	size_t			line = __LINE__,
	string			func = __FUNCTION__,
	const( char )*	msg_end = null
	) nothrow @nogc {
	// Todo(pp): print to stderr
	// Todo(pp): print to custom logger
	if( vkResult != VK_SUCCESS ) {
		import core.stdc.stdio : printf;
		printf( "\n! ERROR !\n==============\n" );
		printf( "\tVkResult : %s\n", vkResult.toCharPtr );
		printHelper( message, file, line, func, msg_end );
	}
	assert( vkResult == VK_SUCCESS );
}


private char[256] buffer;
private void printHelper(
	const( char )* message,
	string file,
	size_t line,
	string func,
	const( char )* msg_end
	) nothrow @nogc {
	import core.stdc.string : memcpy;
	memcpy( buffer.ptr, file.ptr, file.length );
	buffer[ file.length ] = '\0';

	import core.stdc.stdio : printf;
	printf( "\tFile     : %s\n", buffer.ptr );
	printf( "\tLine     : %d\n", line );

	memcpy( buffer.ptr, func.ptr, func.length );
	buffer[ func.length ] = '\0';

	printf( "\tFunc     : %s\n", buffer.ptr );
	if( message ) {
		printf(  "\tMessage  : %s", message );
		if( msg_end ) printf( "%s", msg_end );
		printf(  "\n" );
	}

	printf( "==============\n\n" );
}


const( char )* toCharPtr( VkResult vkResult ) nothrow @nogc {
	switch( vkResult ) {
		case VK_SUCCESS								: return "VK_SUCCESS";
		case VK_NOT_READY							: return "VK_NOT_READY";
		case VK_TIMEOUT								: return "VK_TIMEOUT";
		case VK_EVENT_SET							: return "VK_EVENT_SET";
		case VK_EVENT_RESET							: return "VK_EVENT_RESET";
		case VK_INCOMPLETE							: return "VK_INCOMPLETE";
		case VK_ERROR_OUT_OF_HOST_MEMORY			: return "VK_ERROR_OUT_OF_HOST_MEMORY";
		case VK_ERROR_OUT_OF_DEVICE_MEMORY			: return "VK_ERROR_OUT_OF_DEVICE_MEMORY";
		case VK_ERROR_INITIALIZATION_FAILED			: return "VK_ERROR_INITIALIZATION_FAILED";
		case VK_ERROR_DEVICE_LOST					: return "VK_ERROR_DEVICE_LOST";
		case VK_ERROR_MEMORY_MAP_FAILED				: return "VK_ERROR_MEMORY_MAP_FAILED";
		case VK_ERROR_LAYER_NOT_PRESENT				: return "VK_ERROR_LAYER_NOT_PRESENT";
		case VK_ERROR_EXTENSION_NOT_PRESENT			: return "VK_ERROR_EXTENSION_NOT_PRESENT";
		case VK_ERROR_FEATURE_NOT_PRESENT			: return "VK_ERROR_FEATURE_NOT_PRESENT";
		case VK_ERROR_INCOMPATIBLE_DRIVER			: return "VK_ERROR_INCOMPATIBLE_DRIVER";
		case VK_ERROR_TOO_MANY_OBJECTS				: return "VK_ERROR_TOO_MANY_OBJECTS";
		case VK_ERROR_FORMAT_NOT_SUPPORTED			: return "VK_ERROR_FORMAT_NOT_SUPPORTED";
		case VK_ERROR_FRAGMENTED_POOL				: return "VK_ERROR_FRAGMENTED_POOL";
		case VK_ERROR_SURFACE_LOST_KHR				: return "VK_ERROR_SURFACE_LOST_KHR";
		case VK_ERROR_NATIVE_WINDOW_IN_USE_KHR		: return "VK_ERROR_NATIVE_WINDOW_IN_USE_KHR";
		case VK_SUBOPTIMAL_KHR						: return "VK_SUBOPTIMAL_KHR";
		case VK_ERROR_OUT_OF_DATE_KHR				: return "VK_ERROR_OUT_OF_DATE_KHR";
		case VK_ERROR_INCOMPATIBLE_DISPLAY_KHR		: return "VK_ERROR_INCOMPATIBLE_DISPLAY_KHR";
		case VK_ERROR_VALIDATION_FAILED_EXT			: return "VK_ERROR_VALIDATION_FAILED_EXT";
		case VK_ERROR_INVALID_SHADER_NV				: return "VK_ERROR_INVALID_SHADER_NV";
		case VK_NV_EXTENSION_1_ERROR				: return "VK_NV_EXTENSION_1_ERROR";
		case VK_ERROR_OUT_OF_POOL_MEMORY_KHR		: return "VK_ERROR_OUT_OF_POOL_MEMORY_KHR";
		case VK_ERROR_INVALID_EXTERNAL_HANDLE_KHX	: return "VK_ERROR_INVALID_EXTERNAL_HANDLE_KHX";
		default										: return "UNKNOWN_RESULT"; 
	}
}

/// this is a general templated function to enumarate any vulkan property
/// see usage in module surface or module util.info
auto listVulkanProperty( ReturnType, alias vkFunc, Args... )( Args args ) {
	import vdrive.util.array : ptr;
	Array!ReturnType result;
	VkResult vkResult;
	uint32_t count;

	/*
	* It's possible, though very rare, that the number of
	* instance layers could change. For example, installing something
	* could include new layers that the loader would pick up
	* between the initial query for the count and the
	* request for VkLayerProperties. If that happens,
	* the number of VkLayerProperties could exceed the count
	* previously given. To alert the app to this change
	* vkEnumerateInstanceExtensionProperties will return a VK_INCOMPLETE
	* status.
	* The count parameter will be updated with the number of
	* entries actually loaded into the data pointer.
	*/

	do {
		vkFunc( args, &count, null ).vkAssert;
		if( count == 0 )  break;
		result.length = count;
		vkResult = vkFunc( args, &count, result.ptr );
	} while( vkResult == VK_INCOMPLETE );

	vkResult.vkAssert; // check if everything went right

	return result;
}


/// this is a general templated function to enumarate any vulkan property
/// see usage in module surface or module util.info
/// this overload takes a void* scratch space as first arg and does not allocate
/// scratch memory needs to be sufficiently large, result will be cast and returned in this memory
auto listVulkanProperty( ReturnType, alias vkFunc, Args... )( void* scratch, Args args ) {
	import vdrive.util.array : ptr;
	auto result = ( cast( ReturnType* )scratch )[ 0 .. 1 ];
	VkResult vkResult;
	uint32_t count;

	do {
		vkFunc( args, &count, null ).vkAssert;
		if( count == 0 )  break;
		result = ( cast( ReturnType* )scratch )[ 0 .. count ];
		vkResult = vkFunc( args, &count, &result[0] );
	} while( vkResult == VK_INCOMPLETE );

	vkResult.vkAssert; // check if everything went right

	return result;
}


nothrow:


alias vkMajor = VK_VERSION_MAJOR;
alias vkMinor = VK_VERSION_MINOR;
alias vkPatch = VK_VERSION_PATCH;

alias toUint = toUint32_t;
uint32_t toUint32_t( T )( T value ) if( __traits( isScalar, T )) { 
	return cast( uint32_t )value;
}

alias toInt = toInt32_t;
uint32_t toInt32_t( T )( T value ) if( __traits( isScalar, T )) { 
	return cast( int32_t )value;
}


mixin template Dispatch_To_Inner_Struct( alias inner_struct ) {
	auto opDispatch( string member, Args... )( Args args ) /*pure nothrow*/ {
		static if( args.length == 0 ) {
			static if( __traits( compiles, __traits( getMember, vk, member ))) {
				return __traits( getMember, vk, member );
			} else {
				return __traits( getMember, inner_struct, member );
			}
		} else static if( args.length == 1 )  { 
			__traits( getMember, inner_struct, member ) = args[0];
		} else {
			foreach( arg; args ) writeln( arg );
			assert( 0, "Only one optional argument allowed for dispatching to inner struct: " ~ inner_struct.stringof );
		}
	}
}


// helper template for skipping members
template skipper( string target ) { enum shouldSkip( string s ) = ( s == target ); }

// function which creates to inner struct forwarding functions	
auto Forward_To_Inner_Struct( outer, inner, string path, ignore... )() {
	// import helper template from std.meta to decide if member is found in ignore list
	import std.meta : anySatisfy;
	string result;
	foreach( member; __traits( allMembers, inner )) {
		// https://forum.dlang.org/post/hucredzrhbbjzcesjqbg@forum.dlang.org
		enum skip = anySatisfy!( skipper!( member ).shouldSkip, ignore );		// evaluate if member is in ignore list
		static if( !skip && member != "sType" && member != "pNext" && member != "flags" ) {		// skip, also these
			import vdrive.util.string : snakeCaseCT;							// convertor from camel to snake case
			enum member_snake = member.snakeCaseCT;								// convert to snake case
			//enum result = "\n"												// enum string wich will be mixed in, use only for pragma( msg ) output
			result ~= "\n"
				~ "/// forward member " ~ member ~ " of inner " ~ inner.stringof ~ " as setter function to " ~ outer.stringof ~ "\n"
				~ "/// Params:\n"
				~ "/// \tmeta = reference to a " ~ outer.stringof ~ " struct\n"
				~ "/// \t" ~ member_snake ~ " = the value forwarded to the inner struct\n"
				~ "/// Returns: the passed in Meta_Structure for function chaining\n"
				~ "auto ref " ~ member ~ "( ref " ~ outer.stringof ~ " meta, "
				~ typeof( __traits( getMember,  inner, member )).stringof ~ " " ~ member_snake ~ " ) {\n"
				~ "\t" ~ path ~ "." ~ member ~ " = " ~ member_snake ~ ";\n\treturn meta;\n}\n"
				~ "\n"
				~ "/// forward member " ~ member ~ " of inner " ~ inner.stringof ~ " as getter function to " ~ outer.stringof ~ "\n"
				~ "/// Params:\n"
				~ "/// \tmeta = reference to a " ~ outer.stringof ~ " struct\n"
				~ "/// Returns: copy of " ~ path ~ "." ~ member ~ "\n"
				~ "auto " ~ member ~ "( ref " ~ outer.stringof ~ " meta ) {\n"
				~ "\treturn " ~ path ~ "." ~ member ~ ";\n}\n\n";
			//pragma( msg, result );
			//mixin( result );
		}
	} return result;
}
