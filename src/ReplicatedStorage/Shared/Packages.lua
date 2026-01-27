--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PackagesFolder = ReplicatedStorage:WaitForChild("Packages")

local Packages = {
    --BufferUtil = require(PackagesFolder:WaitForChild("BufferUtil")),
    --Comm = require(PackagesFolder:WaitForChild("Comm")),
    --Component = require(PackagesFolder:WaitForChild("Component")),
    --Concur = require(PackagesFolder:WaitForChild("Concur")),
    --EnumList = require(PackagesFolder:WaitForChild("EnumList")),
    --Find = require(PackagesFolder:WaitForChild("Find")),
    Input = require(PackagesFolder:WaitForChild("Input")),
    Loader = require(PackagesFolder:WaitForChild("Loader")),
    Log = require(PackagesFolder:WaitForChild("Log")),
    --Net = require(PackagesFolder:WaitForChild("Net")),
    --Option = require(PackagesFolder:WaitForChild("Option")),
    --PID = require(PackagesFolder:WaitForChild("PID")),
    --Quaternion = require(PackagesFolder:WaitForChild("Quaternion")),
    --Query = require(PackagesFolder:WaitForChild("Query")),
    --Sequent = require(PackagesFolder:WaitForChild("Sequent")),
    --Ser = require(PackagesFolder:WaitForChild("Ser")),
    Shake = require(PackagesFolder:WaitForChild("Shake")),
    Signal = require(PackagesFolder:WaitForChild("Signal")),
    --Silo = require(PackagesFolder:WaitForChild("Silo")),
    Spring = require(PackagesFolder:WaitForChild("Spring")),
    --Streamable = require(PackagesFolder:WaitForChild("Streamable")),
    --Symbol = require(PackagesFolder:WaitForChild("Symbol")),
    TableUtil = require(PackagesFolder:WaitForChild("TableUtil")),
    --TaskQueue = require(PackagesFolder:WaitForChild("TaskQueue")),
    Timer = require(PackagesFolder:WaitForChild("Timer")),
    --Tree = require(PackagesFolder:WaitForChild("Tree")),
    Trove = require(PackagesFolder:WaitForChild("Trove")),
    --TypedRemote = require(PackagesFolder:WaitForChild("TypedRemote")),
    --WaitFor = require(PackagesFolder:WaitForChild("WaitFor")),
    Packet = require(PackagesFolder:WaitForChild("Packet")),
}

return Packages
