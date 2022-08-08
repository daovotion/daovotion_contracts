//SPDX-License-Identifier:MIT
pragma solidity ^0.8.4;
/**
Conventions:
- All token identifiers should be represented by uint256, as dictated by the ERC1155 standard

 */

/// Convenient struct for listing and ownership
struct DVListNode
{
    // Pointer to next token hash
    uint256 next;
    // Pointer to previous token hash
    uint256 prev; 
}

/**
    Basic double link list of tokens.
 */
struct DVTokenList
{
    // Pointer to list head token hash. (last element)
    uint256 head;
    // number of allocated elements
    uint count;
    /// Registry of entries
    mapping(uint256 => DVListNode) node_registry;
}

/// Derived information from DVTokenOwnershipList
struct DVTokenListInfo
{
    // Pointer to list head token hash. (last element)
    uint256 head;
    // number of allocated elements
    uint count;
}

/**
Advanced list for registering list ownership for tokens.
This asummed that each token has an unique identifier that doesn't repeat.
 */
struct DVTokenOwnershipList
{
    /// Registry of sublists.
    mapping(uint256 => DVListNode) node_registry;

    /// Registry of ownership of sublists for tokens.
    mapping(uint256 => DVTokenListInfo) owner_list_registry;
}


library DVTokenListUtil 
{
    function info(DVTokenList storage listobj) internal view returns(DVTokenListInfo memory)
    {
        return DVTokenListInfo({head:listobj.head, count:listobj.count});
    }

    function clear(DVTokenList storage listobj) internal
    {
        listobj.head = uint256(0);
        listobj.count = uint(0);
    }

    
    /// Removes the peek object from list queue
    function dequeue(DVTokenList storage listobj) internal returns(uint256)
    {
        uint256 _head = listobj.head;
        if(_head == 0) return 0;
        // node and next
        DVListNode storage _head_obj = listobj.node_registry[_head];

        uint256 _next = _head_obj.next;
        _head_obj.next = 0;
        listobj.count--;
        listobj.head = _next;

        if(_next != 0)
        {
            // fix next node
            listobj.node_registry[_next].prev = 0;
        }

        return _head;
    }

    function insert(DVTokenList storage listobj, uint256 newtokenID) internal 
    {
        uint256 currheadID = listobj.head;
        if(currheadID == 0){
            // just insert new entry
            listobj.node_registry[newtokenID] = DVListNode({next:0, prev:0});
            listobj.count = 1;            
        }
        else
        {
            // fix previous token
            DVListNode storage head_obj = listobj.node_registry[currheadID];
            head_obj.prev = newtokenID;
            // register new token
            listobj.node_registry[newtokenID] = DVListNode({next:currheadID, prev:0});
            listobj.count++;
        }

        listobj.head = newtokenID;
    }


    function remove(DVTokenList storage listobj, uint256 extokenID) internal 
    {
        DVListNode storage extoken_obj = listobj.node_registry[extokenID];
        
        uint256 prevID = extoken_obj.prev;
        uint256 nextID = extoken_obj.next;

        if(prevID != 0)
        {
            DVListNode storage prev_obj = listobj.node_registry[prevID];
            prev_obj.next = nextID;
        }
        else        
        {
            // if(extokenID == listobj.head)
            listobj.head = nextID;
        }

        if(nextID != 0)
        {
            DVListNode storage next_obj = listobj.node_registry[nextID];
            next_obj.prev = prevID;
        }

        // may we should use delete, but better to ensure that default values are 0
        delete listobj.node_registry[extokenID];
        listobj.count--;
    }
    
}

//**********************************************************
library DVTokenOwnershipListUtil 
{
    function info(DVTokenOwnershipList storage list_container, uint256 parent_token) internal view returns(DVTokenListInfo memory)
    {
        DVTokenListInfo storage _info = list_container.owner_list_registry[parent_token];
        return DVTokenListInfo({head:_info.head, count:_info.count});
    }    

    function sinfo(DVTokenOwnershipList storage list_container, uint256 parent_token) internal view returns(DVTokenListInfo storage)
    {
        return list_container.owner_list_registry[parent_token];
    }

    function count(DVTokenOwnershipList storage list_container, uint256 parent_token) internal view returns(uint)
    {
        return list_container.owner_list_registry[parent_token].count;
    }

    function init_owner(DVTokenOwnershipList storage list_container, uint256 parent_token) internal
    {
        list_container.owner_list_registry[parent_token] = DVTokenListInfo({head:0,count:0});
    }

    function delete_owner(DVTokenOwnershipList storage list_container, uint256 parent_token) internal
    {
        delete list_container.owner_list_registry[parent_token];
    }

    function insert(DVTokenOwnershipList storage list_container, uint256 parent_token, uint256 newtokenID) internal 
    {
        DVTokenListInfo storage listobj = list_container.owner_list_registry[parent_token];

        uint256 currheadID = listobj.head;// owner list head
        if(currheadID == 0){
            // just insert new sublist entry 
            list_container.node_registry[newtokenID] = DVListNode({next:0, prev:0});
            listobj.count = 1;// update owner
        }
        else
        {
            // fix previous token sublist node
            DVListNode storage head_obj = list_container.node_registry[currheadID];
            head_obj.prev = newtokenID;
            // register new token sublist node
            list_container.node_registry[newtokenID] = DVListNode({next:currheadID, prev:0});
            listobj.count++;// update owner
        }

        listobj.head = newtokenID;
    }


    function remove(DVTokenOwnershipList storage list_container, uint256 parent_token, uint256 extokenID) internal 
    {
        DVTokenListInfo storage listobj = list_container.owner_list_registry[parent_token];

        DVListNode storage extoken_obj = list_container.node_registry[extokenID];

        uint256 prevID = extoken_obj.prev;
        uint256 nextID = extoken_obj.next;

        if(prevID != 0)
        {
            DVListNode storage prev_obj = list_container.node_registry[prevID];
            prev_obj.next = nextID;
        }
        else if(extokenID == listobj.head)
        {
            listobj.head = nextID;
        }

        if(nextID != 0)
        {
            DVListNode storage next_obj = list_container.node_registry[nextID];
            next_obj.prev = prevID;
        }

        // may we should use delete, but better to ensure that default values are 0
        delete list_container.node_registry[extokenID];

        listobj.count--;// update sublist
    }
    
}

/////////////////////////////// Stack /////////////////////////////////////////

/**
    Basic double link list of tokens.
 */
struct DVFreeList
{
    // Pointer to list head token hash. (last element)
    uint256 head;
    // number of allocated elements
    uint count;
    /// Registry of entries, point to next element in the list
    mapping(uint256 => uint256) node_registry;
}

library DVFreeListUtil 
{
    function info(DVFreeList storage listobj) internal view returns(DVTokenListInfo memory)
    {
        return DVTokenListInfo({head:listobj.head, count:listobj.count});
    }

    function clear(DVFreeList storage listobj) internal
    {
        listobj.head = uint256(0);
        listobj.count = uint(0);
    }

    
    /// Removes the peek object from list queue
    function dequeue(DVFreeList storage listobj) internal returns(uint256)
    {
        uint256 _head = listobj.head;
        uint _count = listobj.count;
        if(_head == 0 || _count == 0) return 0;
        // node and next
        uint256 _next = listobj.node_registry[_head];
        
        if(_count == 1)
        {
            // clear list
            listobj.count = 0;
            listobj.head = uint256(0);
        }
        else
        {
            listobj.count = _count - 1;
            listobj.head = _next;
        }

        return _head;
    }

    function insert(DVFreeList storage listobj, uint256 newtokenID) internal 
    {        
        listobj.count++;
        listobj.node_registry[newtokenID] = listobj.head;
        listobj.head = newtokenID;
    }    
}

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
