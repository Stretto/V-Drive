module vdrive.memory;

import core.stdc.stdio : printf;

import vdrive.util;
import vdrive.state;

import erupted;



//////////////////////////////
// general memory functions //
//////////////////////////////

// memory_type_bits is a bitfield where if bit i is set, it means that the VkMemoryType i 
// of the VkPhysicalDeviceMemoryProperties structure satisfies the memory requirements
auto memoryTypeIndex(
    VkPhysicalDeviceMemoryProperties    memory_properties,
    VkMemoryRequirements                memory_requirements,
    VkMemoryPropertyFlags               memory_property_flags
    ) {
    uint32_t memory_type_bits = memory_requirements.memoryTypeBits;
    uint32_t memory_type_index;
    foreach( i; 0u .. memory_properties.memoryTypeCount ) {
        VkMemoryType memory_type = memory_properties.memoryTypes[i];
        if( memory_type_bits & 1 ) {
            if( ( memory_type.propertyFlags & memory_property_flags ) == memory_property_flags ) {
                memory_type_index = i;
                break;
            }
        }
        memory_type_bits = memory_type_bits >> 1;
    }

    return memory_type_index;
}


auto memoryHeapIndex(
    VkPhysicalDeviceMemoryProperties    memory_properties,
    VkMemoryHeapFlags                   memory_heap_flags,
    uint32_t                            first_memory_heap_index = 0
    ) {
    vkAssert( first_memory_heap_index < memory_properties.memoryHeapCount );
    foreach( i; first_memory_heap_index .. memory_properties.memoryHeapCount ) {
        if(( memory_properties.memoryHeaps[i].flags & memory_heap_flags ) == memory_heap_flags ) {
            return i.toUint;
        }
    } return uint32_t.max;
}


auto hasMemoryHeapType(
    VkPhysicalDeviceMemoryProperties    memory_properties,
    VkMemoryHeapFlags                   memory_heap_flags
     ) {
    return memoryHeapIndex( memory_properties, memory_heap_flags ) < uint32_t.max;
}


auto memoryHeapSize(
    VkPhysicalDeviceMemoryProperties    memory_properties,
    uint32_t                            memory_heap_index
    ) {
    vkAssert( memory_heap_index < memory_properties.memoryHeapCount );
    return memory_properties.memoryHeaps[ memory_heap_index ].size;
} 


auto allocateMemory( ref Vulkan vk, VkDeviceSize allocation_size, uint32_t memory_type_index ) {
    // construct a memory allocation info from arguments
    VkMemoryAllocateInfo memory_allocate_info = {
        allocationSize  : allocation_size,
        memoryTypeIndex : memory_type_index,
    };

    // allocate device memory
    VkDeviceMemory device_memory;
    vkAllocateMemory( vk.device, &memory_allocate_info, vk.allocator, &device_memory ).vkAssert;

    return device_memory;
}


auto mapMemory(
    ref Vulkan          vk,
    VkDeviceMemory      memory,
    VkDeviceSize        size,
    VkDeviceSize        offset  = 0,
    VkMemoryMapFlags    flags   = 0,
    string              file    = __FILE__,
    size_t              line    = __LINE__,
    string              func    = __FUNCTION__
    ) {
    void* mapped_memory;
    vk.device.vkMapMemory( memory, offset, size, flags, &mapped_memory ).vkAssert( file, line, func );
    return mapped_memory;
}


void unmapMemory( ref Vulkan vk, VkDeviceMemory memory ) {
    vk.device.vkUnmapMemory( memory );
}



///////////////////////////////////////
// Meta_Memory and related functions //
///////////////////////////////////////

struct Meta_Memory {
    mixin                   Vulkan_State_Pointer;
    private:
    VkDeviceMemory          device_memory;
    VkDeviceSize            device_memory_size = 0;
    VkMemoryPropertyFlags   memory_property_flags = 0;
    uint32_t                memory_type_index;

    public:
    auto memory()           { return device_memory; }
    auto memSize()          { return device_memory_size; }
    auto memPropertyFlags() { return memory_property_flags; }
    auto memTypeIndex()     { return memory_type_index; }

    // bulk destroy the resources belonging to this meta struct
    void destroyResources() {
        vk.destroy( device_memory );
    }
}


auto ref initMemory(
    ref Meta_Memory         meta,
    uint32_t                memory_type_index,
    VkDeviceSize            allocation_size
    ) {
    vkAssert( meta.isValid, "Vulkan state not assigned" );     // assert that meta struct is initialized with a valid vulkan state pointer
    meta.device_memory = allocateMemory( meta, allocation_size, memory_type_index );
    meta.device_memory_size = allocation_size;
    meta.memory_type_index = memory_type_index;
    return meta;
}

alias create = initMemory;



auto createMemory( ref Vulkan vk, uint32_t memory_type_index, VkDeviceSize allocation_size ) {
    Meta_Memory meta = vk;
    meta.create( memory_type_index, allocation_size );
    return meta;
}



auto ref memoryType( ref Meta_Memory meta, VkMemoryPropertyFlags memory_property_flags ) {
    meta.memory_property_flags = memory_property_flags;
    return meta;
}


/// Here we use a trick, we set a very memory type with the lowest index 
/// but set the (same or higher) index manually, the index can be only increased but not decreased
auto ref memoryTypeIndex( ref Meta_Memory meta, uint32_t minimum_index ) {
    if( meta.memory_property_flags == 0 ) meta.memory_property_flags = VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT;
    meta.memory_type_index = minimum_index;
    return meta;
}


auto ref addRange( META )( ref Meta_Memory meta, ref META meta_resource ) if( hasMemReqs!META ) {
    // confirm that VkMemoryPropertyFlags have been specified with memoryType;
    vkAssert( meta.memory_property_flags > 0, "Call memoryType( VkMemoryPropertyFlags ) before adding a range" );

    // get the resource dependent memory type index
    // the lower memory type indices are subsets of the higher type indices regarding the memory properties
    auto resource_type_index = meta_resource.memoryTypeIndex( meta.memory_property_flags );
    if( meta.memory_type_index < resource_type_index ) meta.memory_type_index = resource_type_index;

    // register the require memory size range
    meta_resource.device_memory_offset = meta_resource.alignedOffset( meta.device_memory_size );
    meta.device_memory_size = meta_resource.device_memory_offset + meta_resource.requiredMemorySize;

    return meta;
}


auto ref allocate( ref Meta_Memory meta ) {
    vkAssert( meta.isValid, "Vulkan state not assigned" );     // meta struct must be initialized with a valid vulkan state pointer
    vkAssert( meta.device_memory_size > 0, "Must call addRange() at least onece before calling allocate()" );
    meta.device_memory = allocateMemory( meta, meta.device_memory_size, meta.memory_type_index );
    return meta;
}


auto ref bind( META )( ref Meta_Memory meta, ref META meta_resource ) if( hasMemReqs!META ) {
    vkAssert( meta.device_memory != VK_NULL_HANDLE, "Must allocate() before bind()ing a buffer or image" );        // meta struct must be initialized with a valid vulkan state pointer
    meta_resource.bindMemory( meta.device_memory, meta_resource.device_memory_offset );
    return meta;
}



auto ref initMemory(
    ref Meta_Memory         meta,
    VkMemoryPropertyFlags   memory_property_flags,
    Meta_Buffer[]           meta_buffers,
    Meta_Image[]            meta_images
    ) {
    meta.memory_property_flags = memory_property_flags;
    foreach( ref mb; meta_buffers ) meta.addRange( mb );
    foreach( ref mi; meta_images )  meta.addRange( mi );
    meta.allocate;
    foreach( ref mb; meta_buffers ) meta.bind( mb );
    foreach( ref mi; meta_images )  meta.bind( mi );
    return meta;
}



///////////////////////////////////////////////////////////
// Meta_Buffer and Meta_Image related template functions //
///////////////////////////////////////////////////////////

mixin template Memory_Member() {
    private:
    VkMemoryRequirements    memory_requirements;
    VkDeviceMemory          device_memory;
    VkDeviceSize            device_memory_offset;
    bool                    owns_device_memory = false;
    public:
    auto memory()           { return device_memory; }
    auto memSize()          { return memory_requirements.size; }
    auto memOffset()        { return device_memory_offset; }
    auto memRequirements()  { return memory_requirements; }
}

private template hasMemReqs( T ) { 
    enum hasMemReqs = __traits( hasMember, T, "memory_requirements" );
}


auto memoryTypeIndex( ref Meta_Buffer meta, VkMemoryPropertyFlags memory_property_flags ) {             // can't be a template function as another overload exists already (general function)
    return memoryTypeIndex( meta.memory_properties, meta.memory_requirements, memory_property_flags );
}


auto memoryTypeIndex( ref Meta_Image meta, VkMemoryPropertyFlags memory_property_flags ) {              // can't be a template function as another overload exists already (general function)
    return memoryTypeIndex( meta.memory_properties, meta.memory_requirements, memory_property_flags );
}


auto requiredMemorySize( META )( ref META meta ) if( hasMemReqs!META ) {
    return meta.memory_requirements.size;
}


auto alignedOffset( META )( ref META meta, VkDeviceSize device_memory_offset ) if( hasMemReqs!META ) {
    if( device_memory_offset % meta.memory_requirements.alignment > 0 ) {
        auto alignment = meta.memory_requirements.alignment;
        device_memory_offset = ( device_memory_offset / alignment + 1 ) * alignment;
    }
    return device_memory_offset;
}


/// allocate and bind a VkDeviceMemory object to the VkBuffer/VkImage (which must have been created beforehand) in the meta struct
/// the memory properties of the underlying VkPhysicalDevicethe are used and the resulting memory object is stored
/// The memory object is allocated of the size required by the buffer, another function overload will exist with an argument 
/// for an existing memory object where the buffer is supposed to suballocate its memory from
/// the Meta_Buffer struct is returned for function chaining
auto ref createMemoryImpl( META )(
    ref META                meta,
    VkMemoryPropertyFlags   memory_property_flags,
    string                  file = __FILE__,
    size_t                  line = __LINE__,
    string                  func = __FUNCTION__
    ) if( hasMemReqs!META ) {
    vkAssert( meta.isValid, "Vulkan state not assigned", file, line, func );       // meta struct must be initialized with a valid vulkan state pointer
    if( meta.device_memory != VK_NULL_HANDLE )                  // if device memory is owned and was created already
        meta.destroy( meta.device_memory );                     // we destroy it here
    meta.owns_device_memory = true;
    meta.device_memory = allocateMemory( meta, meta.memory_requirements.size, meta.memoryTypeIndex( memory_property_flags ));
    static if( is( META == Meta_Buffer ))   meta.device.vkBindBufferMemory( meta.buffer, meta.device_memory, 0 ).vkAssert( null, file, line, func );
    else                                    meta.device.vkBindImageMemory(  meta.image,  meta.device_memory, 0 ).vkAssert( null, file, line, func );
    return meta;
}


auto ref bindMemoryImpl( META )(
    ref META        meta,
    VkDeviceMemory  device_memory,
    VkDeviceSize    device_memory_offset = 0,
    string          file = __FILE__,
    size_t          line = __LINE__,
    string          func = __FUNCTION__
    ) if( hasMemReqs!META ) {
    vkAssert( meta.isValid, "Vulkan state not assigned", file, line, func );       // meta struct must be initialized with a valid vulkan state pointer
    vkAssert( meta.device_memory == VK_NULL_HANDLE, "Memory can be bound only once, rebinding is not allowed", file, line, func );
    meta.owns_device_memory = false;
    meta.device_memory = device_memory;
    meta.device_memory_offset = device_memory_offset;
    static if( is( META == Meta_Buffer ))   meta.device.vkBindBufferMemory( meta.buffer, device_memory, device_memory_offset ).vkAssert( null, file, line, func );
    else                                    meta.device.vkBindImageMemory(  meta.image,  device_memory, device_memory_offset ).vkAssert( null, file, line, func );
    return meta;
}


// alias buffer this (in e.g. Meta_Goemetry) does not work with the Impl functions above
// but it does work with the aliases for that functions bellow  
alias createMemory = createMemoryImpl!Meta_Buffer;
alias createMemory = createMemoryImpl!Meta_Image;
alias bindMemory = bindMemoryImpl!Meta_Buffer;
alias bindMemory = bindMemoryImpl!Meta_Image;



/// map the underlying memory object and return the mapped memory pointer
auto mapMemory( META )(
    ref META            meta,
    VkDeviceSize        size    = 0,        // if 0, the meta.device_memory_size will be used
    VkDeviceSize        offset  = 0,
//  VkMemoryMapFlags    flags   = 0,        // for future use
    string              file    = __FILE__,
    size_t              line    = __LINE__,
    string              func    = __FUNCTION__
    ) if( hasMemReqs!META || is( META == Meta_Memory )) {
    // if we want to map the memory of an underlying buffer or image, 
    // we need to account for the buffer or image offset into its VkDeviceMemory
    static if( is( META == Meta_Memory ))   VkDeviceSize combined_offset = offset;
    else                                    VkDeviceSize combined_offset = offset + meta.device_memory_offset;
    if( size == 0 ) size = meta.memSize;    // use the attached memory size in this case
    void* mapped_memory;
    meta.device
        .vkMapMemory( meta.device_memory, combined_offset, size, 0, &mapped_memory )
        .vkAssert( file, line, func );
    return mapped_memory;
}


/// map the underlying memory object, copy the provided data into it and return the mapped memory pointer
auto mapMemory( META )(
    ref META            meta,
    void[]              data,
    VkDeviceSize        offset  = 0,
//  VkMemoryMapFlags    flags   = 0,        // for future use
    string              file    = __FILE__,
    size_t              line    = __LINE__,
    string              func    = __FUNCTION__
    ) if( hasMemReqs!META || is( META == Meta_Memory )) {
    // if we want to map the memory of an underlying buffer or image, 
    // we need to account for the buffer or image offset into its VkDeviceMemory
    static if( is( META == Meta_Memory ))   VkDeviceSize combined_offset = offset;
    else                                    VkDeviceSize combined_offset = offset + meta.device_memory_offset;

    // the same combined_offset logic is applied in the function bellow, so we must pass
    // the original offset to not apply the Meta_Buffer or Meta_Image.device_memory_offset twice
    auto mapped_memory = meta.mapMemory( data.length.toUint, offset, file, line, func );
    mapped_memory[ 0 .. data.length ] = data[];

    // required for the mapped memory flush
    VkMappedMemoryRange flush_mapped_memory_range = {
        memory  : meta.device_memory,
        offset  : combined_offset,
        size    : data.length.toUint,
    };

    // flush the mapped memory range so that its visible to the device memory space
    meta.device
        .vkFlushMappedMemoryRanges( 1, &flush_mapped_memory_range )
        .vkAssert( file, line, func );
    return mapped_memory;
}


/// unmap map the underlying memory object
auto ref unmapMemory( META )( ref META meta ) if( hasMemReqs!META || is( META == Meta_Memory )) {
    meta.device.vkUnmapMemory( meta.device_memory );
    return meta;
}


/// upload data to the VkDeviceMemory object of the coresponding buffer or image through memory mapping
auto ref copyData( META )(
    ref META            meta,
    void[]              data,
    VkDeviceSize        offset  = 0,
//  VkMemoryMapFlags    flags   = 0,        // for future use
    string              file    = __FILE__,
    size_t              line    = __LINE__,
    string              func    = __FUNCTION__
    ) if( hasMemReqs!META || is( META == Meta_Memory )) {
    meta.mapMemory( data, offset, file, line, func );   // this returns the memory pointer, and not the Meta_Struct
    return meta.unmapMemory;
}



///////////////////////////////////////
// Meta_Buffer and related functions //
///////////////////////////////////////

/// struct to capture buffer and memory creation as well as binding
/// the struct can travel through several methods and can be filled with necessary data
/// first thing after creation of this struct must be the assignment of the address of a valid vulkan state struct
/// Here we have a distinction between bufferSize, which is the (requested) size of the VkBuffer
/// and memSeize, which is the size of the memory range attached to the VkBuffer
/// They might differ based on memory granularity and alignment, but both should be safe for memory mapping
struct Meta_Buffer {
    mixin                   Vulkan_State_Pointer;
    VkBuffer                buffer;
    VkBufferCreateInfo      buffer_create_info;
    VkDeviceSize            bufferSize() { return buffer_create_info.size; }

    mixin                   Memory_Member;

    // bulk destroy the resources belonging to this meta struct
    void destroyResources() {
        vk.device.vkDestroyBuffer( buffer, vk.allocator );
        if( owns_device_memory )
            vk.device.vkFreeMemory( device_memory, vk.allocator );
    }
    debug string name;
}


/// initialize a VkBuffer object, this function or createBuffer must be called first, further operations require the buffer
/// the resulting buffer and its create info are stored in the Meta_Buffer struct
/// the Meta_Buffer struct is returned for function chaining
auto ref initBuffer( ref Meta_Buffer meta, VkBufferUsageFlags usage, VkDeviceSize size, VkSharingMode sharing_mode = VK_SHARING_MODE_EXCLUSIVE ) {

    // assert that meta struct is initialized with a valid vulkan state pointer
    assert( meta.isValid );

    // buffer create info from arguments
    meta.buffer_create_info.size        = size; // size in Bytes
    meta.buffer_create_info.usage       = usage;
    meta.buffer_create_info.sharingMode = sharing_mode;
    
    meta.device.vkCreateBuffer( &meta.buffer_create_info, meta.allocator, &meta.buffer ).vkAssert;
    meta.device.vkGetBufferMemoryRequirements( meta.buffer, &meta.memory_requirements );

    return meta;
}

alias create = initBuffer;


/// create a VkBuffer object, this function or initBuffer (or its alias create) must be called first, further operations require the buffer
/// the resulting buffer and its create info are stored in the Meta_Buffer struct
/// the Meta_Buffer struct is returned for function chaining
auto createBuffer( ref Vulkan vk, VkBufferUsageFlags usage, VkDeviceSize size, VkSharingMode sharing_mode = VK_SHARING_MODE_EXCLUSIVE ) {
    Meta_Buffer meta = vk;
    meta.create( usage, size, sharing_mode );
    return meta;
}


/// struct to capture image and memory creation as well as binding
/// the struct can travel through several methods and can be filled with necessary data
/// first thing after creation of this struct must be the assignment of the address of a valid vulkan state struct  
struct Meta_Image {
    mixin                   Vulkan_State_Pointer;
    VkImage                 image = VK_NULL_HANDLE;
    VkImageCreateInfo       image_create_info;
    VkImageView             image_view = VK_NULL_HANDLE;
    VkImageViewCreateInfo   image_view_create_info;

    mixin                   Memory_Member;

    auto resetView() {
        auto result = image_view;
        image_view = VK_NULL_HANDLE;
        return result;
    }

    // bulk destroy the resources belonging to this meta struct
    void destroyResources() {
        vk.device.vkDestroyImage( image, vk.allocator );
        if( image_view != VK_NULL_HANDLE )
            vk.device.vkDestroyImageView( image_view, vk.allocator );
        if( owns_device_memory )
            vk.device.vkFreeMemory( device_memory, vk.allocator );
    }
    debug string name;
}



//////////////////////////////////////
// Meta_Image and related functions //
//////////////////////////////////////

/// init a simple VkImage with one level and one layer, assume VK_IMAGE_TILING_OPTIMAL and VK_SHARING_MODE_EXCLUSIVE
/// store vulkan data in argument Meta_Image container, return container for chaining 
auto ref initImage( 
    ref Meta_Image          meta,
    VkFormat                image_format,
    VkExtent2D              image_extent,
    VkImageUsageFlags       image_usage,
    VkSampleCountFlagBits   image_samples = VK_SAMPLE_COUNT_1_BIT,
    VkSharingMode           sharing_mode = VK_SHARING_MODE_EXCLUSIVE ) {

    vkAssert( meta.isValid, "Vulkan state not assigned" );     // meta struct must be initialized with a valid vulkan state pointer
    VkImageCreateInfo image_create_info = {
        imageType               : VK_IMAGE_TYPE_2D,
        format                  : image_format,                                 // notice me senpai!
        extent                  : { image_extent.width, image_extent.height, 1 },
        mipLevels               : 1,
        arrayLayers             : 1,
        samples                 : image_samples,                                // notice me senpai!
        tiling                  : VK_IMAGE_TILING_OPTIMAL,
        usage                   : image_usage,                                  // notice me senpai!
        sharingMode             : sharing_mode,
        queueFamilyIndexCount   : 0,
        pQueueFamilyIndices     : null,
        initialLayout           : VK_IMAGE_LAYOUT_UNDEFINED,                    // notice me senpai!
    };

    return meta.create( image_create_info );
}

/// init a VkImage, general create image function, gets a VkImageCreateInfo as argument 
/// store vulkan data in argument Meta_Image container, return container for chaining
auto ref initImage( ref Meta_Image meta, const ref VkImageCreateInfo image_create_info ) {
    vkAssert( meta.isValid, "Vulkan state not assigned" ); // meta struct must be initialized with a valid vulkan state pointer
    if( meta.image != VK_NULL_HANDLE )                      // if an VkImage was created with this meta struct already      
        meta.destroy( meta.image );                         // destroy it first
    meta.image_create_info = image_create_info;
    meta.device.vkCreateImage( &meta.image_create_info, meta.allocator, &meta.image ).vkAssert;
    meta.device.vkGetImageMemoryRequirements( meta.image, &meta.memory_requirements );
    return meta;
}

alias create = initImage;

// Todo(pp): add chained functions to edit the meta.image_create_info and finalize with construct(), see module pipeline 



/// create a VkImage, general init image function, gets a VkImageCreateInfo as argument 
/// store vulkan data in argument Meta_Image container, return container for chaining
auto createImage( ref Vulkan vk, const ref VkImageCreateInfo image_create_info ) {
    Meta_Image meta = vk;
    meta.create( image_create_info );
    return meta;
}

/// create a simple VkImage with one level and one layer, assume VK_IMAGE_TILING_OPTIMAL and VK_SHARING_MODE_EXCLUSIVE as default args
/// store vulkan data in argument Meta_Image container, return container for chaining 
auto createImage(
    ref Vulkan              vk,
    VkFormat                image_format,
    VkExtent2D              image_extent,
    VkImageUsageFlags       image_usage,
    VkSampleCountFlagBits   image_samples = VK_SAMPLE_COUNT_1_BIT,
    VkSharingMode           sharing_mode = VK_SHARING_MODE_EXCLUSIVE ) {

    Meta_Image meta = vk;
    meta.create( image_format, image_extent, image_usage, image_samples, sharing_mode );
    return meta;
} 


// TODO(pp): assert that valid memory was bound already to the VkBuffer or VkImage

/// create a VkImageView which closely corresponds to the underlying VkImage type
/// store vulkan data in argument Meta_Image container, return container for chaining
auto ref createView( ref Meta_Image meta, VkImageAspectFlags subrecource_aspect_mask ) {
    VkImageSubresourceRange subresource_range = {
        aspectMask      : subrecource_aspect_mask,
        baseMipLevel    : cast( uint32_t )0,
        levelCount      : meta.image_create_info.mipLevels,
        baseArrayLayer  : cast( uint32_t )0,
        layerCount      : meta.image_create_info.arrayLayers, };
    return meta.createView( subresource_range );
}

/// create a VkImageView which closely coresponds to the underlying VkImage type
/// store vulkan data in argument Meta_Image container, return container for chaining
auto ref createView( ref Meta_Image meta, VkImageSubresourceRange subresource_range ) {
    return meta.createView( subresource_range, cast( VkImageViewType )meta.image_create_info.imageType, meta.image_create_info.format );
}

/// create a VkImageView with choosing an image view type and format for the underlying VkImage, component mapping is identity
/// store vulkan data in argument Meta_Image container, return container for chaining
auto ref createView( ref Meta_Image meta, VkImageSubresourceRange subresource_range, VkImageViewType view_type, VkFormat view_format ) {
    return meta.createView( subresource_range, view_type, view_format, VkComponentMapping(
        VK_COMPONENT_SWIZZLE_IDENTITY, VK_COMPONENT_SWIZZLE_IDENTITY, VK_COMPONENT_SWIZZLE_IDENTITY, VK_COMPONENT_SWIZZLE_IDENTITY ));
}

/// create a VkImageView with choosing an image view type, format and VkComponentMapping for the underlying VkImage
/// store vulkan data in argument Meta_Image container, return container for chaining
auto ref createView( ref Meta_Image meta, VkImageSubresourceRange subresource_range, VkImageViewType view_type, VkFormat view_format, VkComponentMapping component_mapping ) {
    if( meta.image_view != VK_NULL_HANDLE )
        meta.destroy( meta.image_view );
    with( meta.image_view_create_info ) {
        image               = meta.image;
        viewType            = view_type;
        format              = view_format;
        subresourceRange    = subresource_range;
        components          = component_mapping;
    }
    meta.device.vkCreateImageView( &meta.image_view_create_info, meta.allocator, &meta.image_view ).vkAssert;
    return meta;
}


/// records a VkImage transition command in argument command buffer 
void recordTransition(
    VkImage                 image,
    VkCommandBuffer         command_buffer,
    VkImageSubresourceRange subresource_range,
    VkImageLayout           old_layout,
    VkImageLayout           new_layout,
    VkAccessFlags           src_accsess_mask,
    VkAccessFlags           dst_accsess_mask,
    VkPipelineStageFlags    src_stage_mask = VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
    VkPipelineStageFlags    dst_stage_mask = VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
    VkDependencyFlags       dependency_flags = 0, ) {

    VkImageMemoryBarrier layout_transition_barrier = {
        srcAccessMask       : src_accsess_mask,
        dstAccessMask       : dst_accsess_mask,
        oldLayout           : old_layout,
        newLayout           : new_layout,
        srcQueueFamilyIndex : VK_QUEUE_FAMILY_IGNORED,
        dstQueueFamilyIndex : VK_QUEUE_FAMILY_IGNORED,
        image               : image,
        subresourceRange    : subresource_range,
    };

    // Todo(pp): consider using these cases
    
/*  switch (old_image_layout) {
        case VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL:
            image_memory_barrier.srcAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;
            break;

        case VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL:
            image_memory_barrier.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
            break;

        case VK_IMAGE_LAYOUT_PREINITIALIZED:
            image_memory_barrier.srcAccessMask = VK_ACCESS_HOST_WRITE_BIT;
            break;

        default:
            break;
    }

    switch (new_image_layout) {
        case VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL:
            image_memory_barrier.dstAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
            break;

        case VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL:
            image_memory_barrier.dstAccessMask = VK_ACCESS_TRANSFER_READ_BIT;
            break;

        case VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL:
            image_memory_barrier.dstAccessMask = VK_ACCESS_SHADER_READ_BIT;
            break;

        case VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL:
            image_memory_barrier.dstAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;
            break;

        case VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL:
            image_memory_barrier.dstAccessMask = VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT;
            break;

        default:
            break;
    }
*/
    command_buffer.vkCmdPipelineBarrier(
        src_stage_mask, dst_stage_mask, dependency_flags,
        0, null, 0, null, 1, &layout_transition_barrier
    );
}



// checking format support
//VkFormatProperties format_properties;
//vk.gpu.vkGetPhysicalDeviceFormatProperties( VK_FORMAT_B8G8R8A8_UNORM, &format_properties );
//format_properties.printTypeInfo;

// checking image format support (additional capabilities)
//VkImageFormatProperties image_format_properties;
//vk.gpu.vkGetPhysicalDeviceImageFormatProperties(
//  VK_FORMAT_B8G8R8A8_UNORM,
//  VK_IMAGE_TYPE_2D,
//  VK_IMAGE_TILING_OPTIMAL,
//  VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
//  0,
//  &image_format_properties).vkAssert;
//image_format_properties.printTypeInfo;
