pragma solidity ^0.4.13;

contract owned {

  address owner;

  modifier onlyowner() {
    if (msg.sender == owner) {
      _;
    }
  }

  function owned() public {
    owner = msg.sender;
  }
} 
