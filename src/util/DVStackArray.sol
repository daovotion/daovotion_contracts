//SPDX-License-Identifier:MIT
pragma solidity >=0.8.8;

//************ Simple array stack implementation *************************
struct DVStackArray
{
    // number of allocated elements
    uint32 count;
    
    /// Pseudo array
    mapping(uint32 => uint256) array;   
}


library DVStackArrayUtil 
{    
    function clear(DVStackArray storage listobj) internal
    {        
        listobj.count = uint32(0);
    }

    function get(DVStackArray storage listobj, uint32 index) internal view returns(uint256)
    {
        return listobj.array[index];
    }


    /// Gets an element from a hash
    function hget(DVStackArray storage listobj, uint256 ihash) internal view returns(uint256)
    {
        uint32 _count = listobj.count;
        if(_count == 0) return uint256(0);
        uint256 capped = ihash % uint256(_count);
        return listobj.array[uint32(capped)];
    }

    
    /// Removes the peek object from list queue
    function dequeue(DVStackArray storage listobj) internal returns(uint256)
    {
        uint32 _count = listobj.count;
        if(_count == 0) return uint256(0);
        
        _count--;
        listobj.count = _count;
        return listobj.array[_count];
    }

    /**
     * Returns the last index where the element has been inserted
     */
    function insert(DVStackArray storage listobj, uint256 newtokenID) internal returns(uint32)
    {
        uint32 _count = listobj.count;
        listobj.array[_count] = newtokenID;        
        listobj.count = _count + 1;
        return _count;
    }

    /// Swap elements to the last
    /// Returns the new size, and the success flag
    function remove(DVStackArray storage listobj, uint32 index) internal returns (uint32, bool)
    {
        uint32 _count = listobj.count;
        if(index >= _count) return (_count, false);

        _count--;

        if(index < _count)
        {
            // swap with last element
            listobj.array[index] = listobj.array[_count];
        }

        listobj.count = _count;
        return (_count, true);
    }

    function swap_elements(DVStackArray storage listobj, uint32 index0, uint32 index1) internal
    {
        uint32 _count = listobj.count;
        require((index0 < _count) && (index1 < _count) && (index0 != index1), "Wrong element indexes");

        uint256 element0 = listobj.array[index0];
        listobj.array[index0] = listobj.array[index1];
        listobj.array[index1] = element0;
    }

}


//************ Simple array Ownership implementation *************************

// Also is the token mask
uint256 constant DV_MAX_TOKEN_VALUE = (uint256(1) << uint256(224)) - uint256(1);

uint256 constant DV_UPPER_TOKEN_MASK = ~DV_MAX_TOKEN_VALUE;

uint256 constant DV_UPPER_TOKEN_MASK_BIT_COUNT = 224;

uint32 constant INVALID_INDEX32 = 0xffffffff;

/**
 * This collection requires tokens represented as unsigned integers of 224 bits
 */
struct DVOwnershipArray
{

    // Size of each Owner linked collection
    mapping(uint256 => uint32) array_sizes;   

    
    /// Pseudo array
    mapping(uint256 => uint256) ownership;
}

library DVOwnershipArrayUtil 
{    
    function token_index_hash(uint256 token_id, uint32 index) internal pure returns(uint256)
    {
        return (token_id & DV_MAX_TOKEN_VALUE) | (uint256(index) << DV_UPPER_TOKEN_MASK_BIT_COUNT);
    }

    function list_count(DVOwnershipArray storage listobj, uint256 parent_token) internal view returns(uint32)
    {
        return listobj.array_sizes[parent_token];
    }


    function clear(DVOwnershipArray storage listobj, uint256 parent_token) internal
    {        
        listobj.array_sizes[parent_token] = uint32(0);
    }

    function get(DVOwnershipArray storage listobj, uint256 parent_token, uint32 index) internal view returns(uint256)
    {
        uint256 tokenhash = token_index_hash(parent_token, index);
        return listobj.ownership[tokenhash];
    }


    function set(DVOwnershipArray storage listobj, uint256 parent_token, uint32 index, uint256 value) internal
    {
        uint256 tokenhash = token_index_hash(parent_token, index);
        listobj.ownership[tokenhash] = value;
    }

    
    /// Removes the peek object from list queue
    function dequeue(DVOwnershipArray storage listobj, uint256 parent_token) internal returns(uint256)
    {
        uint32 _count = listobj.array_sizes[parent_token];
        if(_count == 0) return uint256(0);
        
        _count--;

        // update count
        listobj.array_sizes[parent_token] = _count;

        // extract element
        uint256 hashindex = token_index_hash(parent_token, _count);
        return listobj.ownership[hashindex];
    }


    /**
     * Returns the index of the last inserted element
     */
    function insert(DVOwnershipArray storage listobj, uint256 parent_token, uint256 newtokenID) internal returns(uint32)
    {
        uint32 _count = listobj.array_sizes[parent_token];
        uint256 hashindex = token_index_hash(parent_token, _count);
        listobj.ownership[hashindex] = newtokenID;
        listobj.array_sizes[parent_token] = _count + 1;
        return _count;
    }

    /// Swap elements to the last
    /// Returns the new size, and the success flag
    function remove(DVOwnershipArray storage listobj, uint256 parent_token, uint32 index) internal returns (uint32, bool)
    {
        uint32 _count = listobj.array_sizes[parent_token];
        if(index >= _count) return (_count, false);

        _count--;

        if(index < _count)
        {
            uint256 hashindex0 = token_index_hash(parent_token, index);
            uint256 hashindex1 = token_index_hash(parent_token, _count);
            // swap with last element
            listobj.ownership[hashindex0] = listobj.ownership[hashindex1];            
        }

        listobj.array_sizes[parent_token] = _count;
        return (_count, true);
    }

    function swap_elements(DVOwnershipArray storage listobj, uint256 parent_token, uint32 index0, uint32 index1) internal
    {
        uint32 _count = listobj.array_sizes[parent_token];        
        require((index0 < _count) && (index1 < _count) && (index0 != index1), "Wrong element indexes");

        uint256 hashindex0 = token_index_hash(parent_token, index0);
        uint256 hashindex1 = token_index_hash(parent_token, index1);
        
        uint256 element0 = listobj.ownership[hashindex0];
        listobj.ownership[hashindex0] = listobj.ownership[hashindex1];
        listobj.ownership[hashindex1] = element0;
    }
}
