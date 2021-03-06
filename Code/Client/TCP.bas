Attribute VB_Name = "TCP"
Option Explicit

'************************************************************
'ABOUT THE TCP MODULE PACKET HEADER COMMENTS
'************************************************************
'All Data_ methods in the TCP module, in both the server and client, are used to handle
'packets coming in to the application (forwarded from GOREsock_DataArrival). These methods
'all contain a comment in their header on how the packet is formatted. For example:
'
'<Name(S)><Class(B)><Etc(L)>
'
'Each <> denotes a different variable. Inside the <>, you see two parts - the name of the
'packet part and the variable type. For example:
'
'<Name(S)>
'
'The name of the packet part is "Name", and the variable type is S. Below is a list
'of all variable types used:
'
'B = Byte (1 byte)
'I = Integer (2 bytes)
'L = Long (4 bytes)
'S = String aka Short String(1 + string length bytes)
'S-EX = StringEX aka Long String (2 + string length bytes)
'************************************************************

Private Type typHOSTENT
    hName As Long
    hAliases As Long
    hAddrType As Integer
    hLength As Integer
    hAddrList As Long
End Type

Private Type WSADATA
    wversion As Integer
    wHighVersion As Integer
    szDescription(0 To 255) As Byte
    szSystemStatus(0 To 127) As Byte
    iMaxSockets As Integer
    iMaxUdpDg As Integer
    lpszVendorInfo As Long
End Type

Private Declare Sub apiCopyMemory Lib "kernel32" Alias "RtlMoveMemory" (hpvDest As Any, ByVal hpvSource As Long, ByVal cbCopy As Long)
Private Declare Function apiGetHostByName Lib "wsock32" Alias "gethostbyname" (ByVal HostName As String) As Long
Private Declare Function WSACleanup Lib "wsock32" () As Long
Private Declare Function WSAStartup Lib "wsock32" (ByVal VersionReq As Long, WSADataReturn As WSADATA) As Long

Private Function IsIP(ByVal IPAddress As String) As Boolean
'************************************************************
'Checks if a string is in a valid IP address format
'More info: http://www.vbgore.com/GameClient.TCP.IsIP
'************************************************************
Dim s() As String
Dim i As Long

    'If there are no periods, I have no idea what we have...
    If InStr(1, IPAddress, ".") = 0 Then Exit Function
    
    'Split up the string by the periods
    s = Split(IPAddress, ".")
    
    'Confirm we have ubound = 3, since xxx.xxx.xxx.xxx has 4 elements and we start at index 0
    If UBound(s) <> 3 Then Exit Function
    
    'Check that the values are numeric and in a valid range
    For i = 0 To 3
        If Val(s(i)) < 0 Then Exit Function
        If Val(s(i)) > 255 Then Exit Function
    Next i
    
    'Looks like we were passed a valid IP!
    IsIP = True
    
End Function

Public Function GetIPFromHost(ByVal HostName As String) As String
'************************************************************
'Returns the IP address given a host name (such as "www.vbgore.com" to 123.45.6.7)
'More info: http://www.vbgore.com/GameClient.TCP.GetIPFromHost
'************************************************************
Dim udtWSAData As WSADATA
Dim HostAddress As Long
Dim HostInfo As typHOSTENT
Dim IPLong As Long
Dim IPBytes() As Byte
Dim i As Integer

    On Error Resume Next
    
    If WSAStartup(257, udtWSAData) Then
        MsgBox "Error initializing winsock on WSAStartup!"
        GetIPFromHost = HostName
        Exit Function
    End If

    'Make sure a HTTP:// or FTP:// something wasn't added... some people like to do that
    If UCase$(Left$(HostName, 7)) = "HTTP://" Then
        HostName = Right$(HostName, Len(HostName) - 7)
    ElseIf UCase$(Left$(HostName, 6)) = "FTP://" Then
        HostName = Right$(HostName, Len(HostName) - 6)
    End If
    
    'If we were already passed an IP, just abort since we have what we want
    If IsIP(HostName) Then
        GetIPFromHost = HostName
        Exit Function
    End If
    
    'Get the host address
    HostAddress = apiGetHostByName(HostName)
    
    'Failure!
    If HostAddress = 0 Then Exit Function
    
    'Move the memory around to get it in a format we can read
    apiCopyMemory HostInfo, HostAddress, LenB(HostInfo)
    apiCopyMemory IPLong, HostInfo.hAddrList, 4
    
    'Get the number of parts to the IP (will always be 4 as far as I know)
    ReDim IPBytes(1 To HostInfo.hLength)

    'Convert the address, stored in the format of a long, to 4 bytes (just simple long -> byte array conversion)
    apiCopyMemory IPBytes(1), IPLong, HostInfo.hLength
    
    'Add in the periods
    For i = 1 To HostInfo.hLength
        GetIPFromHost = GetIPFromHost & IPBytes(i) & "."
    Next
    
    'Remove the final period
    GetIPFromHost = Left$(GetIPFromHost, Len(GetIPFromHost) - 1)
    
    'Clean up the socket
    WSACleanup
    
    On Error GoTo 0

End Function

Sub InitSocket()
'*****************************************************************
'Init the GOREsock socket
'More info: http://www.vbgore.com/GameClient.TCP.InitSocket
'*****************************************************************

    'Save the game ini
    Call Var_Write(DataPath & "Game.ini", "INIT", "Name", UserName)
    If Not SavePass Then   'If the password wont be saved, clear it out
        Call Var_Write(DataPath & "Game.ini", "INIT", "Password", "")
    Else
        Call Var_Write(DataPath & "Game.ini", "INIT", "Password", UserPassword)
    End If
    
    'Clear the SoxID
    SoxID = 0
    
    'Clean out the socket so we can make a fresh new connection
    If frmMain.GOREsock.ShutDown <> soxERROR Then
    
        'Set up the socket
        'Leave the GetIPFromHost() wrapper there, this will convert a host name to IP if needed, or leave it as an IP if you pass an IP
        SoxID = frmMain.GOREsock.Connect(GetIPFromHost("127.0.0.1"), 10200)
        
        'If the SoxID = -1, then the connection failed, elsewise, we're good to go! W00t! ^_^
        If SoxID = -1 Then
            MsgBox "Unable to connect to the game server!" & vbCrLf & "Either the server is down or you are not connected to the internet.", vbOKOnly
        Else
            frmMain.GOREsock.SetOption SoxID, soxSO_TCP_NODELAY, True
        End If

    End If

End Sub

Sub Data_User_Trade_Trade(ByRef rBuf As DataBuffer)
'************************************************************
'Begins the trading sequence
'<Name(S)><MyIndex(B)>
'More info: http://www.vbgore.com/GameClient.TCP.Data_User_Trade_Trade
'************************************************************
Dim i As Long

    For i = 1 To 9
        TradeTable.Trade1(i).Amount = 0
        TradeTable.Trade1(i).Grh = 0
        TradeTable.Trade1(i).Name = vbNullString
        TradeTable.Trade1(i).Value = 0
        TradeTable.Trade2(i).Amount = 0
        TradeTable.Trade2(i).Grh = 0
        TradeTable.Trade2(i).Name = vbNullString
        TradeTable.Trade2(i).Value = 0
    Next i
    TradeTable.Gold1 = 0
    TradeTable.Gold2 = 0
    TradeTable.User1Accepted = 0
    TradeTable.User2Accepted = 0
    TradeTable.User1Name = vbNullString
    TradeTable.User2Name = vbNullString
    TradeTable.MyIndex = 0
    
    TradeTable.User1Name = rBuf.Get_String
    TradeTable.User2Name = rBuf.Get_String
    TradeTable.MyIndex = rBuf.Get_Byte
    ShowGameWindow(TradeWindow) = 1
    LastClickedWindow = TradeWindow

End Sub

Sub Data_User_Trade_UpdateTrade(ByRef rBuf As DataBuffer)
'************************************************************
'Update something about the trade currently taking place
'<UserTableIndex(B)><TableSlot(B)><Amount(L)> (<GrhIndex(L)><ObjName(S)><ObjValue(L)>)
'More info: http://www.vbgore.com/GameClient.TCP.Data_User_Trade_UpdateTrade
'************************************************************
Dim UserTableIndex As Byte
Dim TableSlot As Byte
Dim Amount As Long
Dim GrhIndex As Long
Dim ObjName As String
Dim ObjValue As Long

    UserTableIndex = rBuf.Get_Byte
    TableSlot = rBuf.Get_Byte
    Amount = rBuf.Get_Long

    'Update the gold
    If TableSlot = 0 Then
        If TradeTable.MyIndex = UserTableIndex Then
            TradeTable.Gold1 = Amount
        Else
            TradeTable.Gold2 = Amount
        End If
    
    'Update an item
    ElseIf TableSlot <= 9 Then
        GrhIndex = rBuf.Get_Long
        ObjName = rBuf.Get_String
        ObjValue = rBuf.Get_Long
        If TradeTable.MyIndex = UserTableIndex Then
            TradeTable.Trade1(TableSlot).Amount = Amount
            TradeTable.Trade1(TableSlot).Grh = GrhIndex
            TradeTable.Trade1(TableSlot).Name = ObjName
            TradeTable.Trade1(TableSlot).Value = ObjValue
        Else
            TradeTable.Trade2(TableSlot).Amount = Amount
            TradeTable.Trade2(TableSlot).Grh = GrhIndex
            TradeTable.Trade2(TableSlot).Name = ObjName
            TradeTable.Trade2(TableSlot).Value = ObjValue
        End If
    End If

End Sub

Sub Data_User_Bank_UpdateSlot(ByRef rBuf As DataBuffer)
'************************************************************
'Updates a specific bank item
'<Slot(B)><GrhIndex(L)> If GrhIndex > 0, <Amount(I)>
'More info: http://www.vbgore.com/GameClient.TCP.Data_User_Bank_UpdateSlot
'************************************************************
Dim GrhIndex As Long
Dim Amount As Integer
Dim Slot As Byte

    'Get the values
    Slot = rBuf.Get_Byte
    GrhIndex = rBuf.Get_Long
    
    'Check if to get the amount
    If GrhIndex > 0 Then Amount = rBuf.Get_Integer

    'Update the item
    UserBank(Slot).Amount = Amount
    UserBank(Slot).GrhIndex = GrhIndex

End Sub

Sub Data_User_Bank_Open(ByRef rBuf As DataBuffer)
'************************************************************
'Sends the list of bank items
'Loop: <Slot(B)><GrhIndex(L)><Amount(I)> until Slot = 255
'More info: http://www.vbgore.com/GameClient.TCP.Data_User_Bank_Open
'************************************************************
Dim GrhIndex As Long
Dim Amount As Integer
Dim Slot As Byte

    'Loop through the items until we get the terminator slot (255)
    Do
        
        'Get the slot
        Slot = rBuf.Get_Byte
        
        'Check if we have acquired the terminator slot
        If Slot = 255 Then Exit Do
        
        'Get the amount and obj index
        GrhIndex = rBuf.Get_Long
        Amount = rBuf.Get_Integer
        
        'Store the values
        UserBank(Slot).Amount = Amount
        UserBank(Slot).GrhIndex = GrhIndex
        
    Loop
    
    'Show the bank window
    ShowGameWindow(BankWindow) = 1
    LastClickedWindow = BankWindow

End Sub

Sub Data_Server_MakeProjectile(ByRef rBuf As DataBuffer)
'************************************************************
'Create a projectile from a ranged weapon
'<AttackerIndex(I)><TargetIndex(I)><GrhIndex(L)><Rotate(B)>
'More info: http://www.vbgore.com/GameClient.TCP.Data_Server_MakeProjectile
'************************************************************
Dim AttackerIndex As Integer
Dim TargetIndex As Integer
Dim GrhIndex As Long
Dim Rotate As Byte

    AttackerIndex = rBuf.Get_Integer
    TargetIndex = rBuf.Get_Integer
    GrhIndex = rBuf.Get_Long
    Rotate = rBuf.Get_Byte
    
    'If the char doesn't exist, request to create it
    If Not Engine_ValidChar(AttackerIndex) Then Exit Sub
    If Not Engine_ValidChar(TargetIndex) Then Exit Sub
    
    'Create the projectile
    Engine_Projectile_Create AttackerIndex, TargetIndex, GrhIndex, Rotate
    
End Sub

Sub Data_User_SetWeaponRange(ByRef rBuf As DataBuffer)
'************************************************************
'Set the range of the current weapon used so we can do client-side
' distance checks before sending the attack to the server
'<Range(B)>
'More info: http://www.vbgore.com/GameClient.TCP.Data_User_SetWeaponRange
'************************************************************

    UserAttackRange = rBuf.Get_Byte

End Sub

Sub Data_Server_SetCharSpeed(ByRef rBuf As DataBuffer)
'************************************************************
'Update a char's speed so we can move them the right speed
'<CharIndex(I)><Speed(B)>
'More info: http://www.vbgore.com/GameClient.TCP.Data_Server_SetCharSpeed
'************************************************************
Dim CharIndex As Integer
Dim Speed As Byte

    CharIndex = rBuf.Get_Integer
    Speed = rBuf.Get_Byte
    
    'If the char doesn't exist, request to create it
    If Not Engine_ValidChar(CharIndex) Then Exit Sub
    
    CharList(CharIndex).Speed = Speed

End Sub

Sub Data_Server_Message(ByRef rBuf As DataBuffer)
'************************************************************
'Server sending a common message to client (reccomended you send
' as many messages as possible via this method to save bandwidth)
'<MessageID(B)><...depends on the message>
'More info: http://www.vbgore.com/GameClient.TCP.Data_Server_Message
'************************************************************
Dim MessageID As Byte
Dim TempStr As String
Dim TempInt As Integer
Dim Str1 As String
Dim Str2 As String
Dim Lng1 As Long
Dim Int1 As Integer
Dim Int2 As Integer
Dim Int3 As Integer
Dim Byt1 As Byte

    'Get the message ID
    MessageID = rBuf.Get_Byte
    
    'Check what to do depending on the message ID
    '*** Please refer to the language file for the description of the numbers ***
    Select Case MessageID
        Case 1
            Str1 = rBuf.Get_String
            Engine_AddToChatTextBuffer Replace$(Message(1), "<npcname>", Str1), FontColor_Info
        Case 2
            Engine_AddToChatTextBuffer Message(2), FontColor_Fight
        Case 3
            Lng1 = rBuf.Get_Long
            Engine_AddToChatTextBuffer Replace$(Message(3), "<exp>", Lng1), FontColor_Info
        Case 4
            Lng1 = rBuf.Get_Long
            Engine_AddToChatTextBuffer Replace$(Message(4), "<gold>", Lng1), FontColor_Info
        Case 5
            Byt1 = rBuf.Get_Byte
            Engine_AddToChatTextBuffer Replace$(Message(5), "<skill>", Engine_SkillIDtoSkillName(Byt1)), FontColor_Info
        Case 6
            Byt1 = rBuf.Get_Byte
            Engine_AddToChatTextBuffer Replace$(Message(6), "<skill>", Engine_SkillIDtoSkillName(Byt1)), FontColor_Info
        Case 7
            Engine_AddToChatTextBuffer Message(7), FontColor_Quest
        Case 8
            Engine_AddToChatTextBuffer Message(8), FontColor_Quest
        Case 9
            Int1 = rBuf.Get_Integer
            Str1 = rBuf.Get_String
            Int3 = rBuf.Get_Integer
            TempStr = Replace$(Message(9), "<amount>", Int1)
            TempStr = Replace$(TempStr, "<npcname>", Str1)
            Engine_AddToChatTextBuffer TempStr, FontColor_Quest
            Engine_MakeChatBubble Int3, Engine_WordWrap(TempStr, BubbleMaxWidth)
        Case 10
            Int1 = rBuf.Get_Integer
            Str1 = rBuf.Get_String
            Int3 = rBuf.Get_Integer
            TempStr = Replace$(Message(10), "<amount>", Int1)
            TempStr = Replace$(TempStr, "<objname>", Str1)
            Engine_AddToChatTextBuffer TempStr, FontColor_Quest
            Engine_MakeChatBubble Int3, Engine_WordWrap(TempStr, BubbleMaxWidth)
        Case 11
            Int1 = rBuf.Get_Integer
            Str1 = rBuf.Get_String
            Int2 = rBuf.Get_Integer
            Str2 = rBuf.Get_String
            Int3 = rBuf.Get_Integer
            TempStr = Replace$(Message(11), "<npcamount>", Int1)
            TempStr = Replace$(TempStr, "<npcname>", Str1)
            TempStr = Replace$(TempStr, "<objamount>", Int2)
            TempStr = Replace$(TempStr, "<objname>", Str2)
            Engine_AddToChatTextBuffer TempStr, FontColor_Quest
            Engine_MakeChatBubble Int3, Engine_WordWrap(TempStr, BubbleMaxWidth)
        Case 12
            Engine_AddToChatTextBuffer Message(12), FontColor_Quest
        Case 13
            Str1 = rBuf.Get_String
            Engine_AddToChatTextBuffer Replace$(Message(13), "<name>", Str1), FontColor_Info
        Case 14
            Lng1 = rBuf.Get_Long
            Engine_AddToChatTextBuffer Replace$(Message(14), "<cost>", Lng1), FontColor_Info
        Case 15
            Str1 = rBuf.Get_String
            Engine_AddToChatTextBuffer Replace$(Message(15), "<sender>", Str1), FontColor_Info
        Case 16
            Str1 = rBuf.Get_String
            Engine_AddToChatTextBuffer Replace$(Message(16), "<receiver>", Str1), FontColor_Info
        Case 17
            Engine_AddToChatTextBuffer Message(17), FontColor_Info
        Case 18
            Str1 = rBuf.Get_String
            Engine_AddToChatTextBuffer Replace$(Message(18), "<sender>", Str1), FontColor_Info
        Case 19
            Str1 = rBuf.Get_String
            Engine_AddToChatTextBuffer Replace$(Message(19), "<receiver>", Str1), FontColor_Info
        Case 20
            Engine_AddToChatTextBuffer Message(20), FontColor_Info
        Case 21
            Lng1 = rBuf.Get_Long
            Engine_AddToChatTextBuffer Replace$(Message(21), "<cost>", Lng1), FontColor_Info
        Case 22
            Str1 = rBuf.Get_String
            Engine_AddToChatTextBuffer Replace$(Message(22), "<name>", Str1), FontColor_Info
        Case 23
            Str1 = rBuf.Get_String
            Engine_AddToChatTextBuffer Replace$(Message(23), "<name>", Str1), FontColor_Info
        Case 24
            Engine_AddToChatTextBuffer Message(24), FontColor_Info
        Case 25
            Engine_AddToChatTextBuffer Message(25), FontColor_Info
        Case 26
            Engine_AddToChatTextBuffer Message(26), FontColor_Info
        Case 27
            Int1 = rBuf.Get_Integer
            Str1 = rBuf.Get_String
            TempStr = Replace$(Message(27), "<amount>", Int1)
            Engine_AddToChatTextBuffer Replace$(TempStr, "<name>", Str1), FontColor_Info
        Case 28
            Int1 = rBuf.Get_Integer
            Str1 = rBuf.Get_String
            TempStr = Replace$(Message(28), "<amount>", Int1)
            Engine_AddToChatTextBuffer Replace$(TempStr, "<name>", Str1), FontColor_Info
        Case 29
            Engine_AddToChatTextBuffer Message(29), FontColor_Info
        Case 30
            Str1 = rBuf.Get_String
            Str2 = rBuf.Get_String
            TempStr = Replace$(Message(30), "<name>", Str1)
            Engine_AddToChatTextBuffer Replace$(TempStr, "<desc>", Str2), FontColor_Info
        Case 31
            Str1 = rBuf.Get_String
            Engine_AddToChatTextBuffer Replace$(Message(31), "<name>", Str1), FontColor_Info
        Case 32
            Str1 = rBuf.Get_String
            Engine_AddToChatTextBuffer Replace$(Message(32), "<name>", Str1), FontColor_Info
        Case 33
            Engine_AddToChatTextBuffer Message(33), FontColor_Info
        Case 34
            Engine_AddToChatTextBuffer Message(34), FontColor_Info
        Case 35
            Byt1 = rBuf.Get_Byte
            Engine_AddToChatTextBuffer Replace$(Message(35), "<amount>", Byt1), FontColor_Info
        Case 36
            Engine_AddToChatTextBuffer Message(36), FontColor_Info
        Case 37
            Engine_AddToChatTextBuffer Message(37), FontColor_Info
        Case 38
            Engine_AddToChatTextBuffer Message(38), FontColor_Info
        Case 39
            Str1 = rBuf.Get_String
            Str2 = rBuf.Get_String
            TempStr = Replace$(Message(39), "<skill>", Str1)
            Engine_AddToChatTextBuffer Replace$(TempStr, "<name>", Str2), FontColor_Info
        Case 40
            Str1 = rBuf.Get_String
            Engine_AddToChatTextBuffer Replace$(Message(40), "<name>", Str1), FontColor_Info
        Case 41
            Str1 = rBuf.Get_String
            Int1 = rBuf.Get_Integer
            TempStr = Replace$(Message(41), "<name>", Str1)
            Engine_AddToChatTextBuffer Replace$(TempStr, "<power>", Int1), FontColor_Info
        Case 42
            Str1 = rBuf.Get_String
            Engine_AddToChatTextBuffer Replace$(Message(42), "<name>", Str1), FontColor_Info
        Case 43
            Str1 = rBuf.Get_String
            Int1 = rBuf.Get_Integer
            TempStr = Replace$(Message(43), "<name>", Str1)
            Engine_AddToChatTextBuffer Replace$(TempStr, "<power>", Int1), FontColor_Info
        Case 44
            Str1 = rBuf.Get_String
            Engine_AddToChatTextBuffer Replace$(Message(44), "<name>", Str1), FontColor_Info
        Case 45
            Str1 = rBuf.Get_String
            Int1 = rBuf.Get_Integer
            TempStr = Replace$(Message(45), "<name>", Str1)
            Engine_AddToChatTextBuffer Replace$(TempStr, "<power>", Int1), FontColor_Info
        Case 46
            Str1 = rBuf.Get_String
            Engine_AddToChatTextBuffer Replace$(Message(46), "<name>", Str1), FontColor_Info
        Case 47
            Str1 = rBuf.Get_String
            Int1 = rBuf.Get_Integer
            TempStr = Replace$(Message(47), "<name>", Str1)
            Engine_AddToChatTextBuffer Replace$(TempStr, "<power>", Int1), FontColor_Info
        Case 48
            Engine_AddToChatTextBuffer Message(48), FontColor_Info
        Case 49
            Engine_AddToChatTextBuffer Message(49), FontColor_Info
        Case 50
            Str1 = rBuf.Get_String
            Engine_AddToChatTextBuffer Replace$(Message(50), "<name>", Str1), FontColor_Info
        Case 51
            Engine_AddToChatTextBuffer Message(51), FontColor_Info
        Case 52
            Str1 = rBuf.Get_String
            Str2 = rBuf.Get_String
            TempStr = Replace$(Message(52), "<name>", Str1)
            Engine_AddToChatTextBuffer Replace$(TempStr, "<message>", Str2), FontColor_Talk
            LastWhisperName = Str1  'Set the name of the last person to whisper us
        Case 53
            Str1 = rBuf.Get_String
            Str2 = rBuf.Get_String
            TempStr = Replace$(Message(53), "<name>", Str1)
            Engine_AddToChatTextBuffer Replace$(TempStr, "<message>", Str2), FontColor_Talk
        Case 54
            Str1 = rBuf.Get_String
            Byt1 = rBuf.Get_Byte
            TempStr = Replace$(Message(54), "<name>", Str1)
            Engine_AddToChatTextBuffer Replace$(TempStr, "<value>", Byt1), FontColor_Info
        Case 55
            Lng1 = rBuf.Get_Long
            Engine_AddToChatTextBuffer Replace$(Message(55), "<value>", Lng1), FontColor_Info
        Case 56
            Str1 = rBuf.Get_String
            Engine_AddToChatTextBuffer Replace$(Message(56), "<name>", Str1), FontColor_Info
        Case 57
            Engine_AddToChatTextBuffer Message(57), FontColor_Info
        Case 58
            Str1 = rBuf.Get_String
            Int1 = rBuf.Get_Integer
            TempStr = Replace$(Message(58), "<name>", Str1)
            Engine_AddToChatTextBuffer Replace$(TempStr, "<amount>", Int1), FontColor_Info
        Case 59
            Str1 = rBuf.Get_String
            Int1 = rBuf.Get_Integer
            Int2 = rBuf.Get_Integer
            TempStr = Replace$(Message(59), "<name>", Str1)
            TempStr = Replace$(TempStr, "<amount>", Int1)
            Engine_AddToChatTextBuffer Replace$(TempStr, "<leftover>", Int2), FontColor_Info
        Case 60
            Engine_AddToChatTextBuffer Message(60), FontColor_Info
        Case 61
            Engine_AddToChatTextBuffer Message(61), FontColor_Info
        Case 62
            Lng1 = rBuf.Get_Long
            Engine_AddToChatTextBuffer Replace$(Message(62), "<level>", Lng1), FontColor_Info
        Case 63
            Int1 = rBuf.Get_Integer
            Str1 = rBuf.Get_String
            TempStr = Replace$(Message(63), "<amount>", Int1)
            Engine_AddToChatTextBuffer Replace$(TempStr, "<name>", Str1), FontColor_Info
        Case 64
            Engine_AddToChatTextBuffer Message(64), FontColor_Info
        Case 65
            Int1 = rBuf.Get_Integer
            Str1 = rBuf.Get_String
            TempStr = Replace$(Message(65), "<amount>", Int1)
            Engine_AddToChatTextBuffer Replace$(TempStr, "<name>", Str1), FontColor_Info
        Case 66
            Int1 = rBuf.Get_Integer
            Str1 = rBuf.Get_String
            Int2 = rBuf.Get_Integer
            TempStr = Replace$(Message(66), "<amount>", Int1)
            TempStr = Replace$(TempStr, "<name>", Str1)
            Engine_AddToChatTextBuffer Replace$(TempStr, "<leftover>", Int2), FontColor_Info
        Case 67
            Int1 = rBuf.Get_Integer
            Str1 = rBuf.Get_String
            Lng1 = rBuf.Get_Long
            TempStr = Replace$(Message(67), "<amount>", Int1)
            TempStr = Replace$(TempStr, "<name>", Str1)
            Engine_AddToChatTextBuffer Replace$(TempStr, "<cost>", Lng1), FontColor_Info
        Case 68
            Str1 = rBuf.Get_String
            Engine_AddToChatTextBuffer Replace$(Message(68), "<name>", Str1), FontColor_Info
        Case 69
            Engine_AddToChatTextBuffer Message(69), FontColor_Info
        Case 70
            Engine_AddToChatTextBuffer Message(70), FontColor_Info
        Case 71
            Byt1 = rBuf.Get_Byte
            Engine_AddToChatTextBuffer Replace$(Message(71), "<value>", Byt1), FontColor_Info
        Case 72
            Str1 = rBuf.Get_String
            Engine_AddToChatTextBuffer Replace$(Message(72), "<name>", Str1), FontColor_Info
        Case 73
            Str1 = rBuf.Get_String
            Engine_AddToChatTextBuffer Replace$(Message(73), "<name>", Str1), FontColor_Info
        Case 74
            Int1 = rBuf.Get_Integer
            Int2 = rBuf.Get_Integer
            Str1 = rBuf.Get_String
            TempStr = Replace$(Message(74), "<amount>", Int1)
            TempStr = Replace$(TempStr, "<total>", Int2)
            Engine_AddToChatTextBuffer Replace$(TempStr, "<name>", Str1), FontColor_Quest
        Case 75
            Str1 = rBuf.Get_String
            Engine_AddToChatTextBuffer Replace$(Message(75), "<name>", Str1), FontColor_Info
        Case 76
            Str1 = rBuf.Get_String
            Str2 = rBuf.Get_String
            TempInt = rBuf.Get_Integer
            TempStr = Replace$(Message(76), "<name>", Str1)
            TempStr = Replace$(TempStr, "<message>", Str2)
            Engine_AddToChatTextBuffer TempStr, FontColor_Talk
            If TempInt > 0 Then Engine_MakeChatBubble TempInt, Engine_WordWrap(TempStr, BubbleMaxWidth)
        Case 77
            Str1 = rBuf.Get_String
            Str2 = rBuf.Get_String
            TempStr = Replace$(Message(77), "<name>", Str1)
            Engine_AddToChatTextBuffer Replace$(TempStr, "<gm>", Str2), FontColor_Info
        Case 78
            Int1 = rBuf.Get_Integer
            Engine_AddToChatTextBuffer Replace$(Message(78), "<value>", Int1), FontColor_Info
        Case 79
            MsgBox Message(79)
        Case 80
            Str1 = rBuf.Get_String
            MsgBox Replace$(Message(80), "<name>", Str1)
        Case 81
            MsgBox Message(81)
        Case 82
            MsgBox Message(82)
        Case 83
            MsgBox Message(83)
        Case 84
            MsgBox Message(84)
        Case 85
            MsgBox Message(85)
        Case 86
            Str1 = rBuf.Get_String
            Int1 = rBuf.Get_Integer
            TempStr = Replace$(Message(86), "<name>", Str1)
            Engine_AddToChatTextBuffer Replace$(TempStr, "<amount>", Int1), FontColor_Info
        'Case 87 to 93 - these are only used by the client
        Case 94
            Str1 = rBuf.Get_String
            Engine_AddToChatTextBuffer Replace$(Message(94), "<name>", Str1), FontColor_Info
        Case 95
            Int1 = rBuf.Get_Integer
            Engine_AddToChatTextBuffer Replace$(Message(95), "<index>", Int1), FontColor_Info
        Case 96
            Int1 = rBuf.Get_Integer
            Str1 = rBuf.Get_String
            Lng1 = rBuf.Get_Long
            TempStr = Replace$(Message(96), "<amount>", Int1)
            TempStr = Replace$(TempStr, "<name>", Str1)
            Engine_AddToChatTextBuffer Replace$(TempStr, "<cost>", Lng1), FontColor_Info
        Case 97
            Engine_AddToChatTextBuffer Message(97), FontColor_Info
        Case 98
            Engine_AddToChatTextBuffer Message(98), FontColor_Info
        Case 99
            Engine_AddToChatTextBuffer Message(99), FontColor_Info
        Case 100
            Str1 = rBuf.Get_String
            TempStr = Replace$(Message(100), "<linebreak>", vbCrLf)
            MsgBox Replace$(TempStr, "<reason>", Str1), vbOKOnly Or vbCritical
            IsUnloading = 1
            Engine_UnloadAllForms
        Case 101
            Engine_AddToChatTextBuffer Message(101), FontColor_Info
        Case 102
            Engine_AddToChatTextBuffer Message(102), FontColor_Info
        Case 106
            Str1 = rBuf.Get_String
            Engine_AddToChatTextBuffer Replace$(Message(106), "<name>", Str1), FontColor_Group
        Case 107
            Str1 = rBuf.Get_String
            Engine_AddToChatTextBuffer Replace$(Message(107), "<name>", Str1), FontColor_Group
        Case 108
            Str1 = rBuf.Get_String
            Engine_AddToChatTextBuffer Replace$(Message(108), "<name>", Str1), FontColor_Group
        Case 109
            Engine_AddToChatTextBuffer Message(109), FontColor_Group
        Case 110
            Str1 = rBuf.Get_String
            Engine_AddToChatTextBuffer Replace$(Message(110), "<name>", Str1), FontColor_Group
        Case 111
            Engine_AddToChatTextBuffer Message(111), FontColor_Group
        Case 112
            Engine_AddToChatTextBuffer Message(112), FontColor_Group
        Case 113
            Engine_AddToChatTextBuffer Message(113), FontColor_Group
        Case 114
            Engine_AddToChatTextBuffer Message(114), FontColor_Group
        Case 115
            Str1 = rBuf.Get_String
            Int1 = rBuf.Get_Integer
            TempStr = Replace$(Message(115), "<name>", Str1)
            Engine_AddToChatTextBuffer Replace$(TempStr, "<time>", Int1), FontColor_Group
        Case 116
            Engine_AddToChatTextBuffer Message(116), FontColor_Group
        Case 117
            Lng1 = rBuf.Get_Long
            Engine_AddToChatTextBuffer Replace$(Message(117), "<amount>", Lng1), FontColor_Info
        Case 118
            Lng1 = rBuf.Get_Long
            Engine_AddToChatTextBuffer Replace$(Message(118), "<amount>", Lng1), FontColor_Info
        Case 119
            Engine_AddToChatTextBuffer Message(119), FontColor_Info
        Case 120
            Lng1 = rBuf.Get_Long
            Engine_AddToChatTextBuffer Replace$(Message(120), "<amount>", Lng1), FontColor_Info
        Case 121
            Engine_AddToChatTextBuffer Message(121), FontColor_Info
        Case 123
            Engine_AddToChatTextBuffer Message(123), FontColor_Group
        Case 125
            Engine_AddToChatTextBuffer Message(125), FontColor_Info
        Case 127
            Engine_AddToChatTextBuffer Message(127), FontColor_Info
        Case 128
            Str1 = rBuf.Get_String
            Engine_AddToChatTextBuffer Replace$(Message(128), "<name>", Str1), FontColor_Info
        Case 129
            Byt1 = rBuf.Get_Byte
            If Byt1 <= QuestInfoUBound Then
                Str1 = QuestInfo(Byt1).Name
                QuestInfo(Byt1).Desc = vbNullString
                QuestInfo(Byt1).Name = vbNullString
                Lng1 = QuestInfoUBound
                Do
                    If Lng1 = 0 Then Exit Do
                    If QuestInfo(Lng1).Name <> vbNullString Then Exit Do
                    Lng1 = Lng1 - 1
                Loop
                If Lng1 = 0 Then
                    Erase QuestInfo
                    QuestInfoUBound = 0
                Else
                    ReDim Preserve QuestInfo(1 To Lng1)
                    QuestInfoUBound = Lng1
                End If
                If Str1 <> vbNullString Then
                    Engine_AddToChatTextBuffer Replace$(Message(129), "<name>", Str1), FontColor_Quest
                End If
            End If
        Case 130
            Engine_AddToChatTextBuffer Message(130), FontColor_Info
        Case 131
            Engine_AddToChatTextBuffer Message(131), FontColor_Info
        Case 132
            Engine_AddToChatTextBuffer Message(132), FontColor_Info
        Case 134
            Str1 = rBuf.Get_String
            Engine_AddToChatTextBuffer Replace$(Message(134), "<name>", Str1), FontColor_Quest
        Case 137
            Engine_AddToChatTextBuffer Message(137), FontColor_Info
        Case 138
            Lng1 = rBuf.Get_Long
            Engine_AddToChatTextBuffer Replace$(Message(138), "<amount>", Lng1), FontColor_Info
        Case 139
            Lng1 = rBuf.Get_Long
            Engine_AddToChatTextBuffer Replace$(Message(139), "<amount>", Lng1), FontColor_Info
    End Select

End Sub

Sub Data_Server_Connect()
'************************************************************
'Server is telling the client they have successfully logged in
'<>
'More info: http://www.vbgore.com/GameClient.TCP.Data_Server_Connect
'************************************************************

    'Set the socket state
    SocketOpen = 1

    If EngineRun = False Then
    
        'Load user config
        Game_Config_Load
    
        'Unload the connect form
        Unload frmConnect
    
        'Load main form
        Load frmMain
        frmMain.Visible = True
        frmMain.Show
        frmMain.SetFocus
        Input_Keys_ClearQueue
        DoEvents
            
        'Load the engine
        Engine_Init_TileEngine
    
        'Get the device
        frmMain.Show
        frmMain.SetFocus
        DoEvents
        DIDevice.Acquire
        
        Unload frmNew
        Unload frmConnect
    
    End If
    
    'Send the data
    Data_Send

End Sub

Sub Data_Server_Disconnect()
'************************************************************
'Forces the client to disconnect from the server
'<>
'More info: http://www.vbgore.com/GameClient.TCP.Data_Server_Disconnect
'************************************************************

    IsUnloading = 1

End Sub

Sub Data_Comm_Talk(ByRef rBuf As DataBuffer)
'************************************************************
'Send data to chat buffer
'<Text(S)><FontColorID(B)>(<CharIndex(I)>)
'More info: http://www.vbgore.com/GameClient.TCP.Data_Comm_Talk
'************************************************************
Dim CharIndex As Integer
Dim TempStr As String
Dim TempLng As Long
Dim TempByte As Byte
    
    'Get the text
    TempStr = rBuf.Get_String
    TempByte = rBuf.Get_Byte

    'Filter the temp string
    TempStr = Game_FilterString(TempStr)
    
    'See if we have to make a bubble
    If TempByte And DataCode.Comm_UseBubble Then
        
        'We need a char index
        CharIndex = rBuf.Get_Integer
        
    End If
    
    'Now that we have all the values, check if it is a valid string
    If Not Game_ValidString(TempStr) Then Exit Sub
    
    'Split up the string for our chat bubble and assign it to the character
    If CharIndex > 0 Then
        If CharIndex <= LastChar Then
            Engine_MakeChatBubble CharIndex, Engine_WordWrap(TempStr, BubbleMaxWidth)
        End If
    End If
    
    'Get the color
    Select Case TempByte
        Case DataCode.Comm_FontType_Fight
            TempLng = FontColor_Fight
        Case DataCode.Comm_FontType_Info
            TempLng = FontColor_Info
        Case DataCode.Comm_FontType_Quest
            TempLng = FontColor_Quest
        Case DataCode.Comm_FontType_Talk
            TempLng = FontColor_Talk
        Case DataCode.Comm_FontType_Group
            TempLng = FontColor_Group
        Case Else
            TempLng = FontColor_Talk
    End Select
    
    'Add the text in the text box
    Engine_AddToChatTextBuffer TempStr, TempLng

End Sub

Sub Data_Map_LoadMap(ByRef rBuf As DataBuffer)
'************************************************************
'Load the map the server told us to load
'<MapNum(I)><ServerSideVersion(I)>
'More info: http://www.vbgore.com/GameClient.TCP.Data_Map_LoadMap
'************************************************************
Dim FileNum As Byte
Dim MapNumInt As Integer
Dim SSV As Integer
Dim TempInt As Integer

    'Clear the target character
    TargetCharIndex = 0

    MapNumInt = rBuf.Get_Integer
    SSV = rBuf.Get_Integer

    If Engine_FileExist(MapPath & MapNumInt & ".map", vbNormal) Then  'Get Version Num
        FileNum = FreeFile
        Open MapPath & MapNumInt & ".map" For Binary As #FileNum
            Seek #FileNum, 1
            Get #FileNum, , TempInt
        Close #FileNum
        If TempInt = SSV Then   'Correct Version
            Game_Map_Switch MapNumInt
            sndBuf.Put_Byte DataCode.Map_DoneLoadingMap 'Tell the server we are done loading map
        Else
            'Not correct version
            MsgBox Message(105), vbOKOnly Or vbCritical
            EngineRun = False
            IsUnloading = 1
        End If
    Else
        'Didn't find map
        MsgBox Message(105), vbOKOnly Or vbCritical
        EngineRun = False
        IsUnloading = 1
    End If

End Sub

Sub Data_Map_SendName(ByRef rBuf As DataBuffer)
'************************************************************
'Set the map name and weather
'<Name(S)><Weather(B)><Music(B)>
'More info: http://www.vbgore.com/GameClient.TCP.Data_Map_SendName
'************************************************************
Dim Music As Byte

    MapInfo.Name = rBuf.Get_String
    MapInfo.Weather = rBuf.Get_Byte
    
    'Change the music file if we need to
    Music = rBuf.Get_Byte
    If MapInfo.Music <> Music Then
        Music_Stop 1
        If Music <> 0 Then
            MapInfo.Music = Music
            Music_Load MusicPath & Music & ".mp3", 1
            Music_Play 1
            Music_Volume 86, 1
        End If
    End If
    
End Sub

Sub Data_Send()
'************************************************************
'Send data buffer to the server
'More info: http://www.vbgore.com/GameClient.TCP.Data_Send
'************************************************************

    'Check that we have data to send
    If SocketOpen = 0 Then DoEvents
    If sndBuf.HasBuffer Then
        If SocketOpen = 0 Then DoEvents

        'Send the data
        frmMain.GOREsock.SendData SoxID, sndBuf.Get_Buffer
        
        'Clear the buffer, get it ready for next use
        sndBuf.Clear
  
    End If

End Sub

Sub Data_Server_ChangeCharType(ByRef rBuf As DataBuffer)
'************************************************************
'Change a character by the character index
'<CharIndex(I)><CharType(B)>
'More info: http://www.vbgore.com/GameClient.TCP.Data_Server_ChangeCharType
'************************************************************
Dim CharIndex As Integer
Dim CharType As Byte

    CharIndex = rBuf.Get_Integer
    CharType = rBuf.Get_Byte
    
    'If the char doesn't exist, request to create it
    If Not Engine_ValidChar(CharIndex) Then Exit Sub
    
    'Change the character's type
    CharList(CharIndex).CharType = CharType

End Sub

Sub Data_Server_ChangeChar(ByRef rBuf As DataBuffer)
'************************************************************
'Change a character by the character index
'<CharIndex(I)><Flags(B)>(<Body(I)><Head(I)><Weapon(I)><Hair(I)><Wings(I)>)
'More info: http://www.vbgore.com/GameClient.TCP.Data_Server_ChangeChar
'************************************************************
Dim flags As Byte
Dim CharIndex As Integer
Dim CharBody As Integer
Dim CharHead As Integer
Dim CharWeapon As Integer
Dim CharHair As Integer
Dim CharWings As Integer
Dim DontSetData As Boolean
    
    'Get the character index we are changing
    CharIndex = rBuf.Get_Integer
    
    'Get the flags on what data we need to get
    flags = rBuf.Get_Byte
    
    'If the char doesn't exist, request to create it
    If Not Engine_ValidChar(CharIndex) Then DontSetData = True
    
    'Get the data needed
    If flags And 1 Then
        CharBody = rBuf.Get_Integer
        If Not DontSetData Then CharList(CharIndex).Body = BodyData(CharBody)
    End If
    If flags And 2 Then
        CharHead = rBuf.Get_Integer
        If Not DontSetData Then CharList(CharIndex).Head = HeadData(CharHead)
    End If
    If flags And 4 Then
        CharWeapon = rBuf.Get_Integer
        If Not DontSetData Then CharList(CharIndex).Weapon = WeaponData(CharWeapon)
    End If
    If flags And 8 Then
        CharHair = rBuf.Get_Integer
        If Not DontSetData Then CharList(CharIndex).Hair = HairData(CharHair)
    End If
    If flags And 16 Then
        CharWings = rBuf.Get_Integer
        If Not DontSetData Then CharList(CharIndex).Wings = WingData(CharWings)
    End If
    
End Sub

Sub Data_Server_CharHP(ByRef rBuf As DataBuffer)
'************************************************************
'Set the character HP
'<HP(B)><CharIndex(I)>
'More info: http://www.vbgore.com/GameClient.TCP.Data_Server_CharHP
'************************************************************
Dim CharIndex As Integer
Dim HP As Byte

    HP = rBuf.Get_Byte
    CharIndex = rBuf.Get_Integer

    'If the char doesn't exist, request to create it
    If Not Engine_ValidChar(CharIndex) Then Exit Sub

    CharList(CharIndex).HealthPercent = HP

End Sub

Sub Data_Server_CharMP(ByRef rBuf As DataBuffer)
'************************************************************
'Set the character MP
'<MP(B)><CharIndex(I)>
'More info: http://www.vbgore.com/GameClient.TCP.Data_Server_CharMP
'************************************************************
Dim CharIndex As Integer
Dim MP As Byte

    MP = rBuf.Get_Byte
    CharIndex = rBuf.Get_Integer

    'If the char doesn't exist, request to create it
    If Not Engine_ValidChar(CharIndex) Then Exit Sub

    CharList(CharIndex).ManaPercent = MP

End Sub

Sub Data_Server_EraseChar(ByRef rBuf As DataBuffer)
'************************************************************
'Erase a character by the character index
'<CharIndex(I)>
'More info: http://www.vbgore.com/GameClient.TCP.Data_Server_EraseChar
'************************************************************

    Engine_Char_Erase rBuf.Get_Integer

End Sub

Sub Data_Server_EraseObject(ByRef rBuf As DataBuffer)
'************************************************************
'Erase an object on the object layer
'<X(B)><Y(B)><Grh(L)>
'More info: http://www.vbgore.com/GameClient.TCP.Data_Server_EraseObject
'************************************************************
Dim j As Integer
Dim X As Byte
Dim Y As Byte
Dim Grh As Long

    X = rBuf.Get_Byte
    Y = rBuf.Get_Byte
    Grh = rBuf.Get_Long

    'Loop through until we find the object on (X,Y) then kill it
    For j = 1 To LastObj
        If OBJList(j).Pos.X = X Then
            If OBJList(j).Pos.Y = Y Then
                If OBJList(j).Grh.GrhIndex = Grh Then
                    Engine_OBJ_Erase j
                    Exit Sub
                End If
            End If
        End If
    Next j

End Sub

Sub Data_Server_IconBlessed(ByRef rBuf As DataBuffer)
'************************************************************
'Hide/show blessed icon
'<State(B)><CharIndex(I)>
'More info: http://www.vbgore.com/GameClient.TCP.Data_Server_IconBlessed
'************************************************************
Dim State As Byte
Dim CharIndex As Integer

    State = rBuf.Get_Byte
    CharIndex = rBuf.Get_Integer
    
    'If the char doesn't exist, request to create it
    If Not Engine_ValidChar(CharIndex) Then Exit Sub
    
    CharList(CharIndex).CharStatus.Blessed = State

End Sub

Sub Data_Server_IconCursed(ByRef rBuf As DataBuffer)
'************************************************************
'Hide/show cursed icon
'<State(B)><CharIndex(I)>
'More info: http://www.vbgore.com/GameClient.TCP.Data_Server_IconCursed
'************************************************************
Dim State As Byte
Dim CharIndex As Integer

    State = rBuf.Get_Byte
    CharIndex = rBuf.Get_Integer
    
    'If the char doesn't exist, request to create it
    If Not Engine_ValidChar(CharIndex) Then Exit Sub
    
    CharList(CharIndex).CharStatus.Cursed = State

End Sub

Sub Data_Server_IconIronSkin(ByRef rBuf As DataBuffer)
'************************************************************
'Hide/show ironskinned icon
'<State(B)><CharIndex(I)>
'More info: http://www.vbgore.com/GameClient.TCP.Data_Server_IconIronSkin
'************************************************************
Dim State As Byte
Dim CharIndex As Integer

    State = rBuf.Get_Byte
    CharIndex = rBuf.Get_Integer
    
    'If the char doesn't exist, request to create it
    If Not Engine_ValidChar(CharIndex) Then Exit Sub
    
    CharList(CharIndex).CharStatus.IronSkinned = State

End Sub

Sub Data_Server_IconProtected(ByRef rBuf As DataBuffer)
'************************************************************
'Hide/show protected icon
'<State(B)><CharIndex(I)>
'More info: http://www.vbgore.com/GameClient.TCP.Data_Server_IconProtected
'************************************************************
Dim State As Byte
Dim CharIndex As Integer

    State = rBuf.Get_Byte
    CharIndex = rBuf.Get_Integer
    
    'If the char doesn't exist, request to create it
    If Not Engine_ValidChar(CharIndex) Then Exit Sub
    
    CharList(CharIndex).CharStatus.Protected = State

End Sub

Sub Data_Server_IconSpellExhaustion(ByRef rBuf As DataBuffer)
'************************************************************
'Hide/show spell exhaustion icon
'<State(B)><CharIndex(I)>
'More info: http://www.vbgore.com/GameClient.TCP.Data_Server_IconSpellExhaustion
'************************************************************
Dim State As Byte
Dim CharIndex As Integer

    State = rBuf.Get_Byte
    CharIndex = rBuf.Get_Integer

    'If the char doesn't exist, request to create it
    If Not Engine_ValidChar(CharIndex) Then Exit Sub

    CharList(CharIndex).CharStatus.Exhausted = State

End Sub

Sub Data_Server_IconStrengthened(ByRef rBuf As DataBuffer)
'************************************************************
'Hide/show strengthened icon
'<State(B)><CharIndex(I)>
'More info: http://www.vbgore.com/GameClient.TCP.Data_Server_IconStrengthened
'************************************************************
Dim State As Byte
Dim CharIndex As Integer

    State = rBuf.Get_Byte
    CharIndex = rBuf.Get_Integer
    
    'If the char doesn't exist, request to create it
    If Not Engine_ValidChar(CharIndex) Then Exit Sub
    
    CharList(CharIndex).CharStatus.Strengthened = State

End Sub

Sub Data_Server_IconWarCursed(ByRef rBuf As DataBuffer)
'************************************************************
'Hide/show warcursed icon
'<State(B)><CharIndex(I)>
'More info: http://www.vbgore.com/GameClient.TCP.Data_Server_IconWarCursed
'************************************************************
Dim State As Byte
Dim CharIndex As Integer

    State = rBuf.Get_Byte
    CharIndex = rBuf.Get_Integer
    
    'If the char doesn't exist, request to create it
    If Not Engine_ValidChar(CharIndex) Then Exit Sub

    CharList(CharIndex).CharStatus.WarCursed = State

End Sub

Sub Data_Server_Mailbox(ByRef rBuf As DataBuffer)
'************************************************************
'Recieve the list of messages from a mailbox
'Loop: <New(B)><WriterName(S)><Date(S)><Subject(S)>...<EndFlag(B)>
'More info: http://www.vbgore.com/GameClient.TCP.Data_Server_Mailbox
'************************************************************
Dim NewB As Byte
Dim WName As String
Dim SDate As String
Dim Subj As String

    ShowGameWindow(MailboxWindow) = 1
    
    SelMessage = 0
    LastClickedWindow = MailboxWindow
    MailboxListBuffer = vbNullString
    Do
        NewB = rBuf.Get_Byte
        If NewB = 255 Then Exit Do  'If 1 or 0, it is a message, if 255, it is the EndFlag
        WName = rBuf.Get_String
        SDate = rBuf.Get_String
        Subj = rBuf.Get_String
        MailboxListBuffer = MailboxListBuffer & IIf(NewB, "New - ", "Old - ") & Subj & " - " & WName & " - " & SDate & vbCrLf
    Loop

End Sub

Sub Data_Server_MailItemRemove(ByRef rBuf As DataBuffer)
'************************************************************
'Remove item from mailbox
'<ItemIndex(B)>
'More info: http://www.vbgore.com/GameClient.TCP.Data_Server_MailItemRemove
'************************************************************
Dim ItemIndex As Byte

    ItemIndex = rBuf.Get_Byte

    ReadMailData.Obj(ItemIndex) = 0

End Sub

Sub Data_Server_MailObjUpdate(ByRef rBuf As DataBuffer)
'************************************************************
'Updates the objects in a mail message
'<NumObjs(B)> Loop: <ObjGrhIndex(L)>
'More info: http://www.vbgore.com/GameClient.TCP.Data_Server_MailObjUpdate
'************************************************************
Dim NumObjs As Byte
Dim X As Byte

    'Clear the current objects
    For X = 1 To MaxMailObjs
        ReadMailData.Obj(X) = 0
        ReadMailData.ObjName(X) = 0
        ReadMailData.ObjAmount(X) = 0
    Next X
    
    'Get the number of objects
    NumObjs = rBuf.Get_Byte
    
    'Get the mail objects
    For X = 1 To NumObjs
        ReadMailData.Obj(X) = rBuf.Get_Long
        ReadMailData.ObjName(X) = rBuf.Get_String
        ReadMailData.ObjAmount(X) = rBuf.Get_Integer
    Next X

End Sub

Sub Data_Server_MailMessage(ByRef rBuf As DataBuffer)
'************************************************************
'Recieve message that was requested to be read
'<Message(S-EX)><Subject(S)><WriterName(S)><NumObjs(B)> Loop: <ObjGrhIndex(L)>
'More info: http://www.vbgore.com/GameClient.TCP.Data_Server_MailMessage
'************************************************************
Dim NumObjs As Byte
Dim i As Long

    'Clear the current objects
    For i = 1 To MaxMailObjs
        ReadMailData.Obj(i) = 0
        ReadMailData.ObjName(i) = 0
        ReadMailData.ObjAmount(i) = 0
    Next i
    
    'Show the correct windows
    ShowGameWindow(MailboxWindow) = 0
    ShowGameWindow(ViewMessageWindow) = 1
    LastClickedWindow = ViewMessageWindow
    
    'Get the data
    ReadMailData.Message = rBuf.Get_StringEX
    ReadMailData.Message = Engine_WordWrap(ReadMailData.Message, GameWindow.ViewMessage.Message.Width)
    ReadMailData.Subject = rBuf.Get_String
    ReadMailData.WriterName = rBuf.Get_String
    NumObjs = rBuf.Get_Byte
    For i = 1 To NumObjs
        ReadMailData.Obj(i) = rBuf.Get_Long
        ReadMailData.ObjName(i) = rBuf.Get_String
        ReadMailData.ObjAmount(i) = rBuf.Get_Integer
    Next i

End Sub

Sub Data_Server_MakeCharCached(ByRef rBuf As DataBuffer)
'************************************************************
'Create a character and set their information
'<Flags(I)><Body(I)><Head(I)><Heading(B)><CharIndex(I)><X(B)><Y(B)><Speed(B)><Name(S)><Weapon(I)><Hair(I)><Wings(I)>
' <HP%(B)><MP%(B)><ChatID(B)><CharType(B)> (<OwnerCharIndex(I)>)
'More info: http://www.vbgore.com/GameClient.TCP.Data_Server_MakeCharCached
'************************************************************
Dim flags As Integer
Dim Body As Integer
Dim Head As Integer
Dim Heading As Byte
Dim CharIndex As Integer
Dim X As Byte
Dim Y As Byte
Dim Speed As Byte
Dim Name As String
Dim Weapon As Integer
Dim Hair As Integer
Dim Wings As Integer
Dim HP As Byte
Dim MP As Byte
Dim ChatID As Byte
Dim CharType As Byte
Dim OwnerChar As Integer

    'Retrieve all the information
    flags = rBuf.Get_Integer
    If flags And 1 Then Body = rBuf.Get_Integer Else Body = PacketCache.Server_MakeChar.Body
    If flags And 2 Then Head = rBuf.Get_Integer Else Head = PacketCache.Server_MakeChar.Head
    If flags And 4 Then Heading = rBuf.Get_Byte Else Heading = PacketCache.Server_MakeChar.Heading
    CharIndex = rBuf.Get_Integer
    If flags And 8 Then X = rBuf.Get_Byte Else X = PacketCache.Server_MakeChar.X
    If flags And 16 Then Y = rBuf.Get_Byte Else Y = PacketCache.Server_MakeChar.Y
    If flags And 32 Then Speed = rBuf.Get_Byte Else Speed = PacketCache.Server_MakeChar.Speed
    If flags And 64 Then Name = rBuf.Get_String Else Name = PacketCache.Server_MakeChar.Name
    If flags And 128 Then Weapon = rBuf.Get_Integer Else Weapon = PacketCache.Server_MakeChar.Weapon
    If flags And 256 Then Hair = rBuf.Get_Integer Else Hair = PacketCache.Server_MakeChar.Hair
    If flags And 512 Then Wings = rBuf.Get_Integer Else Wings = PacketCache.Server_MakeChar.Wings
    If flags And 1024 Then HP = rBuf.Get_Byte Else HP = PacketCache.Server_MakeChar.HP
    If flags And 2048 Then MP = rBuf.Get_Byte Else MP = PacketCache.Server_MakeChar.MP
    If flags And 4096 Then ChatID = rBuf.Get_Byte Else ChatID = PacketCache.Server_MakeChar.ChatID
    If flags And 8192 Then CharType = rBuf.Get_Byte Else CharType = PacketCache.Server_MakeChar.CharType
    
    'Check for the owner char index if the char is a slave NPC
    If CharType = ClientCharType_Slave Then OwnerChar = rBuf.Get_Integer
    
    'Store the new values for the cache
    With PacketCache.Server_MakeChar
        .Body = Body
        .Head = Head
        .Heading = Heading
        .X = X
        .Y = Y
        .Speed = Speed
        .Name = Name
        .Weapon = Weapon
        .Hair = Hair
        .Wings = Wings
        .HP = HP
        .MP = MP
        .ChatID = ChatID
        .CharType = CharType
    End With
  
    'Create the character
    Engine_Char_Make CharIndex, Body, Head, Heading, X, Y, Speed, Name, Weapon, Hair, Wings, ChatID, CharType, HP, MP

    'Apply the owner index value
    CharList(CharIndex).OwnerChar = OwnerChar

End Sub

Sub Data_Server_MakeChar(ByRef rBuf As DataBuffer)
'************************************************************
'Create a character and set their information
'<Body(I)><Head(I)><Heading(B)><CharIndex(I)><X(B)><Y(B)><Speed(B)><Name(S)><Weapon(I)><Hair(I)><Wings(I)>
' <HP%(B)><MP%(B)><ChatID(B)><CharType(B)> (<OwnerCharIndex(I)>)
'More info: http://www.vbgore.com/GameClient.TCP.Data_Server_MakeChar
'************************************************************
Dim Body As Integer
Dim Head As Integer
Dim Heading As Byte
Dim CharIndex As Integer
Dim X As Byte
Dim Y As Byte
Dim Speed As Byte
Dim Name As String
Dim Weapon As Integer
Dim Hair As Integer
Dim Wings As Integer
Dim HP As Byte
Dim MP As Byte
Dim ChatID As Byte
Dim CharType As Byte
Dim OwnerChar As Integer

    'Retrieve all the information
    Body = rBuf.Get_Integer
    Head = rBuf.Get_Integer
    Heading = rBuf.Get_Byte
    CharIndex = rBuf.Get_Integer
    X = rBuf.Get_Byte
    Y = rBuf.Get_Byte
    Speed = rBuf.Get_Byte
    Name = rBuf.Get_String
    Weapon = rBuf.Get_Integer
    Hair = rBuf.Get_Integer
    Wings = rBuf.Get_Integer
    HP = rBuf.Get_Byte
    MP = rBuf.Get_Byte
    ChatID = rBuf.Get_Byte
    CharType = rBuf.Get_Byte
    
    'Check for the owner char index if the char is a slave NPC
    If CharType = ClientCharType_Slave Then OwnerChar = rBuf.Get_Integer
    
    'Create the character
    Engine_Char_Make CharIndex, Body, Head, Heading, X, Y, Speed, Name, Weapon, Hair, Wings, ChatID, CharType, HP, MP

    'Apply the owner index value
    CharList(CharIndex).OwnerChar = OwnerChar

End Sub

Sub Data_Server_MakeObject(ByRef rBuf As DataBuffer)
'************************************************************
'Create an object on the object layer
'<GrhIndex(L)><X(B)><Y(B)>
'More info: http://www.vbgore.com/GameClient.TCP.Data_Server_MakeObject
'************************************************************
Dim GrhIndex As Long
Dim X As Byte
Dim Y As Byte

    'Get the values
    GrhIndex = rBuf.Get_Long
    X = rBuf.Get_Byte
    Y = rBuf.Get_Byte

    'Create the object
    If GrhIndex > 0 Then Engine_OBJ_Create GrhIndex, X, Y

End Sub

Sub Data_Server_MoveChar(ByRef rBuf As DataBuffer)
'************************************************************
'Move a character
'<CharIndex(I)><X(B)><Y(B)><Heading(B)>
'More info: http://www.vbgore.com/GameClient.TCP.Data_Server_MoveChar
'************************************************************
Dim CharIndex As Integer
Dim X As Integer
Dim Y As Integer
Dim nX As Integer
Dim nY As Integer
Dim Heading As Byte
Dim Running As Byte
    
    CharIndex = rBuf.Get_Integer
    X = rBuf.Get_Byte
    Y = rBuf.Get_Byte
    Heading = rBuf.Get_Byte
    
    'If the char doesn't exist, request to create it
    If Not Engine_ValidChar(CharIndex) Then Exit Sub
    
    'Check if running
    If Heading > 128 Then
        Heading = Heading Xor 128
        Running = 1
    End If
    
    'Make sure the char is the right starting position
    Select Case Heading
        Case NORTH: nX = 0: nY = -1
        Case EAST: nX = 1: nY = 0
        Case SOUTH: nX = 0: nY = 1
        Case WEST: nX = -1: nY = 0
        Case NORTHEAST: nX = 1: nY = -1
        Case SOUTHEAST: nX = 1: nY = 1
        Case SOUTHWEST: nX = -1: nY = 1
        Case NORTHWEST: nX = -1: nY = -1
    End Select
    CharList(CharIndex).Pos.X = X - nX
    CharList(CharIndex).Pos.Y = Y - nY
    
    'Move the character
    Engine_Char_Move_ByPos CharIndex, X, Y, Running

End Sub

Sub Data_Server_PlaySound(ByRef rBuf As DataBuffer)
'************************************************************
'Play a wave file
'<WaveNum(B)>
'More info: http://www.vbgore.com/GameClient.TCP.Data_Server_PlaySound
'************************************************************
Dim WaveNum As Byte

    WaveNum = rBuf.Get_Byte
    
    'Check that we are using sounds
    If UseSfx = 0 Then Exit Sub
    
    'Create the buffer if needed
    If SoundBufferTimer(WaveNum) < timeGetTime Then
        If DSBuffer(WaveNum) Is Nothing Then Sound_Set DSBuffer(WaveNum), WaveNum
    End If
    
    'Update the timer
    SoundBufferTimer(WaveNum) = timeGetTime + SoundBufferTimerMax

    Sound_Play DSBuffer(WaveNum), DSBPLAY_DEFAULT

End Sub

Sub Data_Server_PlaySound3D(ByRef rBuf As DataBuffer)
'************************************************************
'Play a wave file with 3D effect
'<WaveNum(B)><X(B)><Y(B)>
'More info: http://www.vbgore.com/GameClient.TCP.Data_Server_PlaySound3D
'************************************************************
Dim WaveNum As Byte
Dim X As Integer
Dim Y As Integer

    WaveNum = rBuf.Get_Byte
    X = rBuf.Get_Byte
    Y = rBuf.Get_Byte
    
    Sound_Play3D WaveNum, X, Y

End Sub

Sub Data_Server_SetCharDamage(ByRef rBuf As DataBuffer)
'************************************************************
'Damage a character and display it
'<CharIndex(I)><Damage(I)>
'More info: http://www.vbgore.com/GameClient.TCP.Data_Server_SetCharDamage
'************************************************************
Dim CharIndex As Integer
Dim Damage As Integer

    CharIndex = rBuf.Get_Integer
    Damage = rBuf.Get_Integer
    
    'If the char doesn't exist, request to create it
    If Not Engine_ValidChar(CharIndex) Then Exit Sub

    'Create the blood (if damage)
    If Damage > 0 Then Engine_Blood_Create CharList(CharIndex).Pos.X, CharList(CharIndex).Pos.Y

    'Create the damage
    Engine_Damage_Create CharList(CharIndex).Pos.X, CharList(CharIndex).Pos.Y, Damage
    
    'Aggressive face
    If Damage > 0 Then
        CharList(CharIndex).Aggressive = 1
        CharList(CharIndex).AggressiveCounter = timeGetTime + AGGRESSIVEFACETIME
    End If
    
End Sub

Sub Data_Server_SetUserPosition(ByRef rBuf As DataBuffer)
'************************************************************
'Set the user's position
'<X(B)><Y(B)>
'More info: http://www.vbgore.com/GameClient.TCP.Data_Server_SetUserPosition
'************************************************************
Dim X As Byte
Dim Y As Byte

    'Get the position
    X = rBuf.Get_Byte
    Y = rBuf.Get_Byte

    'Check for a valid range
    If X < 1 Then Exit Sub
    If X > MapInfo.Width Then Exit Sub
    If Y < 1 Then Exit Sub
    If Y > MapInfo.Height Then Exit Sub

    'Check for a valid UserCharIndex
    If UserCharIndex <= 0 Or UserCharIndex > LastChar Then
    
        'We have an invalid user char index, so we must have the wrong one - request an update on the right one
        sndBuf.Put_Byte DataCode.User_RequestUserCharIndex
        Exit Sub
        
    End If

    'Check if the position is even different
    If X <> UserPos.X Or Y <> UserPos.Y Then
    
        'Update the user's position
        UserPos.X = X
        UserPos.Y = Y
        CharList(UserCharIndex).Pos = UserPos

        'If there is a targeted char, check if the path is valid
        If TargetCharIndex > 0 Then
            If TargetCharIndex <= LastChar Then
                On Error Resume Next    'Sometimes something strange will cause this to fail when a target dies - just ignore it
                    ClearPathToTarget = Engine_ClearPath(CharList(UserCharIndex).Pos.X, CharList(UserCharIndex).Pos.Y, CharList(TargetCharIndex).Pos.X, CharList(TargetCharIndex).Pos.Y)
                On Error GoTo 0
            End If
        End If
        
    End If

End Sub

Sub Data_Server_UserCharIndex(ByRef rBuf As DataBuffer)
'************************************************************
'Set the user character index
'<CharIndex(I)>
'More info: http://www.vbgore.com/GameClient.TCP.Data_Server_UserCharIndex
'************************************************************

    'Retrieve the index of the user's character
    UserCharIndex = rBuf.Get_Integer
    UserPos = CharList(UserCharIndex).Pos
    
    'Update the map-bound sound effects
    Sound_UpdateMap

End Sub

Sub Data_Combo_SlashSoundRotateDamage(ByRef rBuf As DataBuffer)
'************************************************************
'Combines slash, 3d sound, damage and rotation packets together
'<AttackerIndex(I)><TargetIndex(I)><SlashGrh(L)><Sfx(B)><Damage(I)>
'More info: http://www.vbgore.com/GameClient.TCP.Data_Combo_SlashSoundRotateDamage
'************************************************************
Dim AttackerIndex As Integer
Dim TargetIndex As Integer
Dim SlashGrh As Long
Dim Sfx As Byte
Dim Damage As Integer
Dim NewHeading As Byte
Dim Angle As Integer

    AttackerIndex = rBuf.Get_Integer
    TargetIndex = rBuf.Get_Integer
    SlashGrh = rBuf.Get_Long
    Sfx = rBuf.Get_Byte
    Damage = rBuf.Get_Integer

    'If the char doesn't exist, request to create it
    If Not Engine_ValidChar(AttackerIndex) Then Exit Sub
    If Not Engine_ValidChar(TargetIndex) Then Exit Sub
    
    'Rotate the AttackerIndex to face TargetIndex
    NewHeading = Engine_FindDirection(CharList(AttackerIndex).Pos, CharList(TargetIndex).Pos)
    CharList(AttackerIndex).HeadHeading = NewHeading
    CharList(AttackerIndex).Heading = NewHeading
    
    'Get the new heading
    Select Case CharList(AttackerIndex).Heading
        Case NORTH
            Angle = 0
        Case NORTHEAST
            Angle = 45
        Case EAST
            Angle = 90
        Case SOUTHEAST
            Angle = 135
        Case SOUTH
            Angle = 180
        Case SOUTHWEST
            Angle = 225
        Case WEST
            Angle = 270
        Case NORTHWEST
            Angle = 315
    End Select

    'Create the effect
    Engine_Effect_Create CharList(AttackerIndex).Pos.X, CharList(AttackerIndex).Pos.Y, SlashGrh, Angle, 150, 0
    
    'Play the sound
    Sound_Play3D Sfx, CharList(AttackerIndex).Pos.X, CharList(AttackerIndex).Pos.Y
    
    'Create the blood (if damage)
    If Damage > 0 Then Engine_Blood_Create CharList(TargetIndex).Pos.X, CharList(TargetIndex).Pos.Y

    'Create the damage
    Engine_Damage_Create CharList(TargetIndex).Pos.X, CharList(TargetIndex).Pos.Y, Damage
    
    'Start the attack animation
    CharList(AttackerIndex).Body.Attack(CharList(AttackerIndex).Heading).Started = 1
    CharList(AttackerIndex).Body.Attack(CharList(AttackerIndex).Heading).FrameCounter = 1
    CharList(AttackerIndex).Body.Attack(CharList(AttackerIndex).Heading).LastCount = timeGetTime
    CharList(AttackerIndex).Weapon.Attack(CharList(AttackerIndex).Heading).FrameCounter = 1
    CharList(AttackerIndex).ActionIndex = 2
    
    'Aggressive face
    If Damage > 0 Then
        CharList(TargetIndex).Aggressive = 1
        CharList(TargetIndex).AggressiveCounter = timeGetTime + AGGRESSIVEFACETIME
    End If

End Sub

Sub Data_Combo_ProjectileSoundRotateDamage(ByRef rBuf As DataBuffer)
'************************************************************
'Combines projectile, 3d sound, damage and rotation packets together
'<AttackerIndex(I)><TargetIndex(I)><ProjectileGrh(L)><RotateSpeed(B)><Sfx(B)><Damage(I)>
'More info: http://www.vbgore.com/GameClient.TCP.Data_Combo_ProjectileSoundRotateDamage
'************************************************************
Dim AttackerIndex As Integer
Dim TargetIndex As Integer
Dim GrhIndex As Long
Dim RotateSpeed As Byte
Dim Sfx As Byte
Dim NewHeading As Byte
Dim Damage As Integer

    AttackerIndex = rBuf.Get_Integer
    TargetIndex = rBuf.Get_Integer
    GrhIndex = rBuf.Get_Long
    RotateSpeed = rBuf.Get_Byte
    Sfx = rBuf.Get_Byte
    Damage = rBuf.Get_Integer

    'If the char doesn't exist, request to create it
    If Not Engine_ValidChar(AttackerIndex) Then Exit Sub
    If Not Engine_ValidChar(TargetIndex) Then Exit Sub
    
    'Rotate the AttackerIndex to face TargetIndex
    NewHeading = Engine_FindDirection(CharList(AttackerIndex).Pos, CharList(TargetIndex).Pos)
    CharList(AttackerIndex).HeadHeading = NewHeading
    CharList(AttackerIndex).Heading = NewHeading
    
    'Create the projectile
    Engine_Projectile_Create AttackerIndex, TargetIndex, GrhIndex, RotateSpeed

    'Play the sound
    Sound_Play3D Sfx, CharList(AttackerIndex).Pos.X, CharList(AttackerIndex).Pos.Y
    
    'Create the blood (if damage)
    If Damage > 0 Then Engine_Blood_Create CharList(TargetIndex).Pos.X, CharList(TargetIndex).Pos.Y

    'Start the attack animation
    CharList(AttackerIndex).Body.Attack(CharList(AttackerIndex).Heading).Started = 1
    CharList(AttackerIndex).Body.Attack(CharList(AttackerIndex).Heading).FrameCounter = 1
    CharList(AttackerIndex).Body.Attack(CharList(AttackerIndex).Heading).LastCount = timeGetTime
    CharList(AttackerIndex).Weapon.Attack(CharList(AttackerIndex).Heading).FrameCounter = 1
    CharList(AttackerIndex).ActionIndex = 2

    'Create the damage
    Engine_Damage_Create CharList(TargetIndex).Pos.X, CharList(TargetIndex).Pos.Y, Damage
    
    'Aggressive face
    If Damage > 0 Then
        CharList(TargetIndex).Aggressive = 1
        CharList(TargetIndex).AggressiveCounter = timeGetTime + AGGRESSIVEFACETIME
    End If

End Sub

Sub Data_Combo_SoundRotateDamage(ByRef rBuf As DataBuffer)
'************************************************************
'Combines sound playing, damage and rotation packets together
'<AttackerIndex(I)><TargetIndex(I)><Sfx(B)><Damage(I)>
'More info: http://www.vbgore.com/GameClient.TCP.Data_Combo_SoundRotateDamage
'************************************************************
Dim AttackerIndex As Integer
Dim TargetIndex As Integer
Dim Damage As Integer
Dim Sfx As Byte
Dim NewHeading As Byte

    AttackerIndex = rBuf.Get_Integer
    TargetIndex = rBuf.Get_Integer
    Sfx = rBuf.Get_Byte
    Damage = rBuf.Get_Integer
    
    'If the char doesn't exist, request to create it
    If Not Engine_ValidChar(AttackerIndex) Then Exit Sub
    If Not Engine_ValidChar(TargetIndex) Then Exit Sub

    'Rotate the AttackerIndex to face TargetIndex
    NewHeading = Engine_FindDirection(CharList(AttackerIndex).Pos, CharList(TargetIndex).Pos)
    CharList(AttackerIndex).HeadHeading = NewHeading
    CharList(AttackerIndex).Heading = NewHeading
    
    'Play the sound
    Sound_Play3D Sfx, CharList(AttackerIndex).Pos.X, CharList(AttackerIndex).Pos.Y
    
    'Start the attack animation
    CharList(AttackerIndex).Body.Attack(CharList(AttackerIndex).Heading).Started = 1
    CharList(AttackerIndex).Body.Attack(CharList(AttackerIndex).Heading).FrameCounter = 1
    CharList(AttackerIndex).Body.Attack(CharList(AttackerIndex).Heading).LastCount = timeGetTime
    CharList(AttackerIndex).Weapon.Attack(CharList(AttackerIndex).Heading).FrameCounter = 1
    CharList(AttackerIndex).ActionIndex = 2
    
    'Create the blood (if damage)
    If Damage > 0 Then Engine_Blood_Create CharList(TargetIndex).Pos.X, CharList(TargetIndex).Pos.Y

    'Create the damage
    Engine_Damage_Create CharList(TargetIndex).Pos.X, CharList(TargetIndex).Pos.Y, Damage
    
    'Aggressive face
    If Damage > 0 Then
        CharList(TargetIndex).Aggressive = 1
        CharList(TargetIndex).AggressiveCounter = timeGetTime + AGGRESSIVEFACETIME
    End If

End Sub

Sub Data_User_Attack(ByRef rBuf As DataBuffer)
'************************************************************
'Change character animation to attack animation
'<CharIndex(I)>
'More info: http://www.vbgore.com/GameClient.TCP.Data_User_Attack
'************************************************************
Dim CharIndex As Integer

    CharIndex = rBuf.Get_Integer
    
    'If the char doesn't exist, request to create it
    If Not Engine_ValidChar(CharIndex) Then Exit Sub
    
    'Start the attack animation
    CharList(CharIndex).Body.Attack(CharList(CharIndex).Heading).Started = 1
    CharList(CharIndex).Body.Attack(CharList(CharIndex).Heading).FrameCounter = 1
    CharList(CharIndex).Body.Attack(CharList(CharIndex).Heading).LastCount = timeGetTime
    CharList(CharIndex).Weapon.Attack(CharList(CharIndex).Heading).FrameCounter = 1
    CharList(CharIndex).ActionIndex = 2

End Sub

Sub Data_User_BaseStat(ByRef rBuf As DataBuffer)
'************************************************************
'Update base stat
'<StatID(B)><Value(L)>
'More info: http://www.vbgore.com/GameClient.TCP.Data_User_BaseStat
'************************************************************
Dim StatID As Byte

    StatID = rBuf.Get_Byte
    BaseStats(StatID) = rBuf.Get_Long

End Sub

Sub Data_User_Blink(ByRef rBuf As DataBuffer)
'************************************************************
'Make a character blink
'<CharIndex(I)>
'More info: http://www.vbgore.com/GameClient.TCP.Data_User_Blink
'************************************************************
Dim CharIndex As Integer

    CharIndex = rBuf.Get_Integer
    
    'If the char doesn't exist, request to create it
    If Not Engine_ValidChar(CharIndex) Then Exit Sub

    CharList(CharIndex).StartBlinkTimer = 0
    CharList(CharIndex).BlinkTimer = 0

End Sub

Sub Data_User_CastSkill(ByRef rBuf As DataBuffer)
'************************************************************
'User casted a skill
'<SkillID(B)> (Rest depends on the SkillID)
'More info: http://www.vbgore.com/GameClient.TCP.Data_User_CastSkill
'************************************************************
Dim CasterIndex As Integer
Dim TargetIndex As Integer
Dim TempIndex As Integer
Dim SkillID As Byte
Dim X As Long
Dim Y As Long

    SkillID = rBuf.Get_Byte
    
    Select Case SkillID

    Case SkID.Heal
    
        CasterIndex = rBuf.Get_Integer
        TargetIndex = rBuf.Get_Integer
        If Not Engine_ValidChar(CasterIndex) Then Exit Sub
        If Not Engine_ValidChar(TargetIndex) Then Exit Sub

        'Set the position
        X = Engine_TPtoSPX(CharList(CasterIndex).Pos.X) + 16
        Y = Engine_TPtoSPY(CharList(CasterIndex).Pos.Y)

        'If not casted on self, bind to character
        If TargetIndex <> CasterIndex Then
            TempIndex = Effect_Heal_Begin(X, Y, 3, 120, 1)
            Effect(TempIndex).BindToChar = TargetIndex
            Effect(TempIndex).BindSpeed = 7
        Else
            TempIndex = Effect_Heal_Begin(X, Y, 3, 120, 0)
        End If

    Case SkID.Protection
    
        CasterIndex = rBuf.Get_Integer
        TargetIndex = rBuf.Get_Integer
        If Not Engine_ValidChar(CasterIndex) Then Exit Sub
        If Not Engine_ValidChar(TargetIndex) Then Exit Sub

        'Create the effect at (not bound to) the target character
        X = Engine_TPtoSPX(CharList(TargetIndex).Pos.X) + 16
        Y = Engine_TPtoSPY(CharList(TargetIndex).Pos.Y)
        TempIndex = Effect_Protection_Begin(X, Y, 11, 120, 40, 15)
        Effect(TempIndex).BindToChar = TargetIndex
        Effect(TempIndex).BindSpeed = 25

    Case SkID.Strengthen
    
        CasterIndex = rBuf.Get_Integer
        TargetIndex = rBuf.Get_Integer
        If Not Engine_ValidChar(CasterIndex) Then Exit Sub
        If Not Engine_ValidChar(TargetIndex) Then Exit Sub

        'Create the effect at (not bound to) the target character
        X = Engine_TPtoSPX(CharList(TargetIndex).Pos.X) + 16
        Y = Engine_TPtoSPY(CharList(TargetIndex).Pos.Y)
        TempIndex = Effect_Strengthen_Begin(X, Y, 12, 120, 40, 15)
        Effect(TempIndex).BindToChar = TargetIndex
        Effect(TempIndex).BindSpeed = 25

    Case SkID.Bless
    
        CasterIndex = rBuf.Get_Integer
        TargetIndex = rBuf.Get_Integer
        If Not Engine_ValidChar(CasterIndex) Then Exit Sub
        If Not Engine_ValidChar(TargetIndex) Then Exit Sub

        'Create the effect
        X = Engine_TPtoSPX(CharList(TargetIndex).Pos.X) + 16
        Y = Engine_TPtoSPY(CharList(TargetIndex).Pos.Y)
        TempIndex = Effect_Bless_Begin(X, Y, 3, 120, 40, 15)
        Effect(TempIndex).BindToChar = TargetIndex
        Effect(TempIndex).BindSpeed = 25
        
    Case SkID.SummonBandit
    
        TargetIndex = rBuf.Get_Integer
        If Not Engine_ValidChar(TargetIndex) Then Exit Sub
        X = Engine_TPtoSPX(CharList(TargetIndex).Pos.X) + 16
        Y = Engine_TPtoSPY(CharList(TargetIndex).Pos.Y)
        
        'Create the effect
        TempIndex = Effect_Summon_Begin(X, Y, 1, 500, 0)
        Effect(TempIndex).BindToChar = TargetIndex
        Effect(TempIndex).BindSpeed = 25

    Case SkID.SpikeField
    
        CasterIndex = rBuf.Get_Integer
        If Not Engine_ValidChar(CasterIndex) Then Exit Sub

        'Create the spike field depending on the direction the user is facing
        X = CharList(CasterIndex).Pos.X
        Y = CharList(CasterIndex).Pos.Y
        If CharList(CasterIndex).HeadHeading = NORTH Or CharList(CasterIndex).HeadHeading = NORTHEAST Then
            Engine_Effect_Create X - 1, Y + 1, 59
            Engine_Effect_Create X, Y + 1, 59
            Engine_Effect_Create X + 1, Y + 1, 59

            Engine_Effect_Create X - 2, Y, 59, , , , 0.5
            Engine_Effect_Create X - 1, Y, 59, , , , 0.5
            Engine_Effect_Create X, Y, 59, , , , 0.5
            Engine_Effect_Create X + 1, Y, 59, , , , 0.5
            Engine_Effect_Create X + 2, Y, 59, , , , 0.5

            Engine_Effect_Create X - 2, Y - 1, 59, , , , 1
            Engine_Effect_Create X - 1, Y - 1, 59, , , , 1
            Engine_Effect_Create X, Y - 1, 59, , , , 1
            Engine_Effect_Create X + 1, Y - 1, 59, , , , 1
            Engine_Effect_Create X + 2, Y - 1, 59, , , , 1

            Engine_Effect_Create X - 2, Y - 2, 59, , , , 1.5
            Engine_Effect_Create X - 1, Y - 2, 59, , , , 1.5
            Engine_Effect_Create X, Y - 2, 59, , , , 1.5
            Engine_Effect_Create X + 1, Y - 2, 59, , , , 1.5
            Engine_Effect_Create X + 2, Y - 2, 59, , , , 1.5

            Engine_Effect_Create X - 1, Y - 3, 59, , , , 2
            Engine_Effect_Create X, Y - 3, 59, , , , 2
            Engine_Effect_Create X + 1, Y - 3, 59, , , , 2

            Engine_Effect_Create X, Y - 4, 59, , , , 2.5
        ElseIf CharList(CasterIndex).HeadHeading = EAST Or CharList(CasterIndex).HeadHeading = SOUTHEAST Then
            Engine_Effect_Create X - 1, Y - 1, 59
            Engine_Effect_Create X - 1, Y, 59
            Engine_Effect_Create X - 1, Y + 1, 59

            Engine_Effect_Create X, Y - 2, 59, , , , 0.5
            Engine_Effect_Create X, Y - 1, 59, , , , 0.5
            Engine_Effect_Create X, Y, 59, , , , 0.5
            Engine_Effect_Create X, Y + 1, 59, , , , 0.5
            Engine_Effect_Create X, Y + 2, 59, , , , 0.5

            Engine_Effect_Create X + 1, Y - 2, 59, , , , 1
            Engine_Effect_Create X + 1, Y - 1, 59, , , , 1
            Engine_Effect_Create X + 1, Y, 59, , , , 1
            Engine_Effect_Create X + 1, Y + 1, 59, , , , 1
            Engine_Effect_Create X + 1, Y + 2, 59, , , , 1

            Engine_Effect_Create X + 2, Y - 2, 59, , , , 1.5
            Engine_Effect_Create X + 2, Y - 1, 59, , , , 1.5
            Engine_Effect_Create X + 2, Y, 59, , , , 1.5
            Engine_Effect_Create X + 2, Y + 1, 59, , , , 1.5
            Engine_Effect_Create X + 2, Y + 2, 59, , , , 1.5

            Engine_Effect_Create X + 3, Y - 1, 59, , , , 2
            Engine_Effect_Create X + 3, Y, 59, , , , 2
            Engine_Effect_Create X + 3, Y + 1, 59, , , , 2

            Engine_Effect_Create X + 4, Y, 59, , , , 2.5
        ElseIf CharList(CasterIndex).HeadHeading = SOUTH Or CharList(CasterIndex).HeadHeading = SOUTHWEST Then
            Engine_Effect_Create X - 1, Y - 1, 59
            Engine_Effect_Create X, Y - 1, 59
            Engine_Effect_Create X + 1, Y - 1, 59

            Engine_Effect_Create X - 2, Y, 59, , , , 0.5
            Engine_Effect_Create X - 1, Y, 59, , , , 0.5
            Engine_Effect_Create X, Y, 59, , , , 0.5
            Engine_Effect_Create X + 1, Y, 59, , , , 0.5
            Engine_Effect_Create X + 2, Y, 59, , , , 0.5

            Engine_Effect_Create X - 2, Y + 1, 59, , , , 1
            Engine_Effect_Create X - 1, Y + 1, 59, , , , 1
            Engine_Effect_Create X, Y + 1, 59, , , , 1
            Engine_Effect_Create X + 1, Y + 1, 59, , , , 1
            Engine_Effect_Create X + 2, Y + 1, 59, , , , 1

            Engine_Effect_Create X - 2, Y + 2, 59, , , , 1.5
            Engine_Effect_Create X - 1, Y + 2, 59, , , , 1.5
            Engine_Effect_Create X, Y + 2, 59, , , , 1.5
            Engine_Effect_Create X + 1, Y + 2, 59, , , , 1.5
            Engine_Effect_Create X + 2, Y + 2, 59, , , , 1.5

            Engine_Effect_Create X - 1, Y + 3, 59, , , , 2
            Engine_Effect_Create X, Y + 3, 59, , , , 2
            Engine_Effect_Create X + 1, Y + 3, 59, , , , 2

            Engine_Effect_Create X, Y + 4, 59, , , , 2.5
        ElseIf CharList(CasterIndex).HeadHeading = WEST Or CharList(CasterIndex).HeadHeading = NORTHWEST Then
            Engine_Effect_Create X + 1, Y - 1, 59
            Engine_Effect_Create X + 1, Y, 59
            Engine_Effect_Create X + 1, Y + 1, 59

            Engine_Effect_Create X, Y - 2, 59, , , , 0.5
            Engine_Effect_Create X, Y - 1, 59, , , , 0.5
            Engine_Effect_Create X, Y, 59, , , , 0.5
            Engine_Effect_Create X, Y + 1, 59, , , , 0.5
            Engine_Effect_Create X, Y + 2, 59, , , , 0.5

            Engine_Effect_Create X - 1, Y - 2, 59, , , , 1
            Engine_Effect_Create X - 1, Y - 1, 59, , , , 1
            Engine_Effect_Create X - 1, Y, 59, , , , 1
            Engine_Effect_Create X - 1, Y + 1, 59, , , , 1
            Engine_Effect_Create X - 1, Y + 2, 59, , , , 1

            Engine_Effect_Create X - 2, Y - 2, 59, , , , 1.5
            Engine_Effect_Create X - 2, Y - 1, 59, , , , 1.5
            Engine_Effect_Create X - 2, Y, 59, , , , 1.5
            Engine_Effect_Create X - 2, Y + 1, 59, , , , 1.5
            Engine_Effect_Create X - 2, Y + 2, 59, , , , 1.5

            Engine_Effect_Create X - 3, Y - 1, 59, , , , 2
            Engine_Effect_Create X - 3, Y, 59, , , , 2
            Engine_Effect_Create X - 3, Y + 1, 59, , , , 2

            Engine_Effect_Create X - 4, Y, 59, , , , 2.5
        End If

    End Select

End Sub

Sub Data_Server_MakeEffect(ByRef rBuf As DataBuffer)
'************************************************************
'Create an effect on the effects layer
'<X(B)><Y(B)><GrhIndex(L)>
'More info: http://www.vbgore.com/GameClient.TCP.Data_Server_MakeEffect
'************************************************************
Dim X As Byte
Dim Y As Byte
Dim GrhIndex As Long

    'Get the values
    X = rBuf.Get_Byte
    Y = rBuf.Get_Byte
    GrhIndex = rBuf.Get_Long

    'Create the effect
    Engine_Effect_Create X, Y, GrhIndex, 0, 0, 1
    
End Sub

Sub Data_Server_MakeSlash(ByRef rBuf As DataBuffer)
'************************************************************
'Create a slash effect on the effects layer
'<CharIndex(I)><GrhIndex(L)>
'More info: http://www.vbgore.com/GameClient.TCP.Data_Server_MakeSlash
'************************************************************
Dim CharIndex As Integer
Dim GrhIndex As Long
Dim Angle As Single
    
    'Get the values
    CharIndex = rBuf.Get_Integer
    GrhIndex = rBuf.Get_Long
    
    'If the char doesn't exist, request to create it
    If Not Engine_ValidChar(CharIndex) Then Exit Sub
    
    'Get the new heading
    Select Case CharList(CharIndex).Heading
        Case NORTH
            Angle = 0
        Case NORTHEAST
            Angle = 45
        Case EAST
            Angle = 90
        Case SOUTHEAST
            Angle = 135
        Case SOUTH
            Angle = 180
        Case SOUTHWEST
            Angle = 225
        Case WEST
            Angle = 270
        Case NORTHWEST
            Angle = 315
    End Select

    'Create the effect
    Engine_Effect_Create CharList(CharIndex).Pos.X, CharList(CharIndex).Pos.Y, GrhIndex, Angle, 150, 0
    
End Sub

Sub Data_User_Emote(ByRef rBuf As DataBuffer)
'************************************************************
'A character uses an emoticon
'<EmoticonIndex(B)><CharIndex(I)>
'More info: http://www.vbgore.com/GameClient.TCP.Data_User_Emote
'************************************************************
Dim EmoticonIndex As Byte
Dim CharIndex As Integer

    EmoticonIndex = rBuf.Get_Byte
    CharIndex = rBuf.Get_Integer

    'If the char doesn't exist, request to create it
    If Not Engine_ValidChar(CharIndex) Then Exit Sub

    'Reset the fade value
    CharList(CharIndex).EmoFade = 0
    CharList(CharIndex).EmoDir = 1

    'Set the user's emoticon Grh by the emoticon index
    'Grh values are pulled directly from Grh1.raw - refer to that file
    Select Case EmoticonIndex
    Case EmoID.Dots: Engine_Init_Grh CharList(CharIndex).Emoticon, 78
    Case EmoID.Exclimation: Engine_Init_Grh CharList(CharIndex).Emoticon, 81
    Case EmoID.Question: Engine_Init_Grh CharList(CharIndex).Emoticon, 84
    Case EmoID.Surprised: Engine_Init_Grh CharList(CharIndex).Emoticon, 87
    Case EmoID.Heart: Engine_Init_Grh CharList(CharIndex).Emoticon, 90
    Case EmoID.Hearts: Engine_Init_Grh CharList(CharIndex).Emoticon, 93
    Case EmoID.HeartBroken: Engine_Init_Grh CharList(CharIndex).Emoticon, 96
    Case EmoID.Utensils: Engine_Init_Grh CharList(CharIndex).Emoticon, 99
    Case EmoID.Meat: Engine_Init_Grh CharList(CharIndex).Emoticon, 102
    Case EmoID.ExcliQuestion: Engine_Init_Grh CharList(CharIndex).Emoticon, 105
    End Select

End Sub

Sub Data_User_KnownSkills(ByRef rBuf As DataBuffer)
'************************************************************
'Retrieve known skills list
'<KnowSkillList()(B)>
'More info: http://www.vbgore.com/GameClient.TCP.Data_User_KnownSkills
'************************************************************
Dim KnowSkillList() As Long 'Note that each byte holds 8 skills
Dim Index As Long   'Which KnowSkillList array index to use
Dim X As Byte
Dim Y As Byte
Dim i As Byte

    'Retrieve the skill list
    ReDim KnowSkillList(1 To NumBytesForSkills)
    For i = 1 To NumBytesForSkills
        KnowSkillList(i) = rBuf.Get_Byte
    Next i
    
    'Clear the skill list size
    SkillListSize = 0

    'Set the values
    For i = 1 To NumSkills
        
        'Find the index to use
        Index = Int((i - 1) / 8) + 1
    
        'Check if the skill is known
        If KnowSkillList(Index) And (2 ^ (i - ((Index - 1) * 8) - 1)) Then

            'Update the SkillList position and size
            SkillListSize = SkillListSize + 1
            ReDim Preserve SkillList(1 To SkillListSize)

            'Set that the user knows the skill
            UserKnowSkill(i) = 1

            'Update position for skill list
            X = X + 1
            If X > SkillListWidth Then
                X = 1
                Y = Y + 1
            End If

            'Set the skill list ID and Position
            SkillList(SkillListSize).SkillID = i
            SkillList(SkillListSize).X = SkillListX - (X * 32)
            SkillList(SkillListSize).Y = SkillListY - (Y * 32)

        Else
        
            'User does not know the skill
            UserKnowSkill(i) = 0
            
        End If
    Next i

End Sub

Sub Data_User_LookLeft(ByRef rBuf As DataBuffer)
'************************************************************
'Make a character look to the specified direction (Used for LookLeft and LookRight)
'<CharIndex(I)><Heading(B)>
'More info: http://www.vbgore.com/GameClient.TCP.Data_User_LookLeft
'************************************************************
Dim CharIndex As Integer
Dim Heading As Byte

    CharIndex = rBuf.Get_Integer
    Heading = rBuf.Get_Byte
    
    'If the char doesn't exist, request to create it
    If Not Engine_ValidChar(CharIndex) Then Exit Sub

    CharList(CharIndex).HeadHeading = Heading

End Sub

Sub Data_User_ModStat(ByRef rBuf As DataBuffer)
'************************************************************
'Update mod stat
'<StatID(B)><Value(L)>
'More info: http://www.vbgore.com/GameClient.TCP.Data_User_ModStat
'************************************************************
Dim StatID As Byte

    StatID = rBuf.Get_Byte
    ModStats(StatID) = rBuf.Get_Long

End Sub

Sub Data_User_Rotate(ByRef rBuf As DataBuffer)
'************************************************************
'Rotate a character by their CharIndex - works like it does in
' ChangeChar, but used to save ourselves a little bandwidth :)
'<CharIndex(I)><Heading(B)>
'More info: http://www.vbgore.com/GameClient.TCP.Data_User_Rotate
'************************************************************
Dim Heading As Byte
Dim CharIndex As Integer
    
    CharIndex = rBuf.Get_Integer
    Heading = rBuf.Get_Byte
    
    'If the char doesn't exist, request to create it
    If Not Engine_ValidChar(CharIndex) Then Exit Sub
    
    CharList(CharIndex).Heading = Heading
    CharList(CharIndex).HeadHeading = CharList(CharIndex).Heading

End Sub

Sub Data_User_SetInventorySlot(ByRef rBuf As DataBuffer)
'************************************************************
'Set an inventory slot's information
'The information in the () is only sent if the ObjIndex <> 0
'<Slot(B)><OBJIndex(L)>(<OBJName(S)><OBJAmount(L)><Equipted(B)><GrhIndex(L)>)
'More info: http://www.vbgore.com/GameClient.TCP.Data_User_SetInventorySlot
'************************************************************
Dim Slot As Byte

    'Get the slot
    Slot = rBuf.Get_Byte

    'Start gathering the data
    UserInventory(Slot).ObjIndex = rBuf.Get_Long
    
    'If the object index = 0, then we are deleting a slot, so the rest is null
    If UserInventory(Slot).ObjIndex = 0 Then
        UserInventory(Slot).Name = "(None)"
        UserInventory(Slot).Amount = 0
        UserInventory(Slot).Equipped = 0
        UserInventory(Slot).GrhIndex = 0
        UserInventory(Slot).Value = 0
    Else
        'Index <> 0, so we have to get the information
        UserInventory(Slot).Name = rBuf.Get_String
        UserInventory(Slot).Amount = rBuf.Get_Long
        UserInventory(Slot).Equipped = rBuf.Get_Byte
        UserInventory(Slot).GrhIndex = rBuf.Get_Long
        UserInventory(Slot).Value = rBuf.Get_Long
    End If

End Sub

Sub Data_User_Target(ByRef rBuf As DataBuffer)
'************************************************************
'User targets a character
'<CharIndex(I)>
'More info: http://www.vbgore.com/GameClient.TCP.Data_User_Target
'************************************************************

    TargetCharIndex = rBuf.Get_Integer
    
    'Check for a valid UserCharIndex
    If UserCharIndex <= 0 Or UserCharIndex > LastChar Then
    
        'We have an invalid user char index, so we must have the wrong one - request an update on the right one
        sndBuf.Put_Byte DataCode.User_RequestUserCharIndex
        Exit Sub
        
    End If
    
    'Check if the path to the targeted character is valid (if any)
    If TargetCharIndex > 0 Then ClearPathToTarget = Engine_ClearPath(CharList(UserCharIndex).Pos.X, CharList(UserCharIndex).Pos.Y, CharList(TargetCharIndex).Pos.X, CharList(TargetCharIndex).Pos.Y)

End Sub

Sub Data_User_ChangeServer(ByRef rBuf As DataBuffer)
'************************************************************
'Changes a user to a different server
'<Port(I)><IP(S)>
'More info: http://www.vbgore.com/GameClient.TCP.Data_User_ChangeServer
'************************************************************
Dim Port As Integer
Dim IP As String

    'Get the values
    Port = rBuf.Get_Integer
    IP = rBuf.Get_String

    'Clean out the socket so we can make a fresh new connection
    If SocketOpen = 1 Then
        SocketOpen = 0
        frmMain.GOREsock.Shut SoxID
    End If
    
    'Set the variables to move to the new server
    SocketMoveToIP = IP
    SocketMoveToPort = Port
    
    'Clear the map
    CurMap = 0

End Sub

Sub Data_User_Trade_StartNPCTrade(ByRef rBuf As DataBuffer)
'************************************************************
'Start trading with a NPC
'<NPCName(S)><NumVendItems(I)> Loop: <GrhIndex(L)><Name(S)><Price(L)>
'More info: http://www.vbgore.com/GameClient.TCP.Data_User_Trade_StartNPCTrade
'************************************************************
Dim NPCName As String
Dim NumItems As Integer
Dim Item As Integer

    NPCName = rBuf.Get_String
    NumItems = rBuf.Get_Integer

    ReDim NPCTradeItems(1 To NumItems)
    NPCTradeItemArraySize = NumItems
    For Item = 1 To NumItems
        NPCTradeItems(Item).GrhIndex = rBuf.Get_Long
        NPCTradeItems(Item).Name = rBuf.Get_String
        NPCTradeItems(Item).Value = rBuf.Get_Long
    Next Item
    ShowGameWindow(ShopWindow) = 1
    LastClickedWindow = ShopWindow

End Sub

Sub Data_User_Trade_Accept(ByRef rBuf As DataBuffer)
'************************************************************
'One of the users of the trade has pressed the accept button
'<UserTableIndex(B)>
'More info: http://www.vbgore.com/GameClient.TCP.Data_User_Trade_Accept
'************************************************************
Dim UserTableIndex As Byte

    UserTableIndex = rBuf.Get_Byte
    
    'Find which name to high-light
    If UserTableIndex = 1 Then
        If TradeTable.MyIndex = 1 Then TradeTable.User1Accepted = 1 Else TradeTable.User2Accepted = 1
    Else
        If TradeTable.MyIndex = 2 Then TradeTable.User1Accepted = 1 Else TradeTable.User2Accepted = 1
    End If

End Sub

Sub Data_User_Trade_Cancel()
'************************************************************
'Trade table was closed or canceled
'<>
'More info: http://www.vbgore.com/GameClient.TCP.Data_User_Trade_Cancel
'************************************************************
Dim i As Long

    ShowGameWindow(TradeWindow) = 0
    If LastClickedWindow = TradeWindow Then LastClickedWindow = 0

    For i = 1 To 9
        TradeTable.Trade1(i).Amount = 0
        TradeTable.Trade1(i).Grh = 0
        TradeTable.Trade1(i).Name = vbNullString
        TradeTable.Trade1(i).Value = 0
        TradeTable.Trade2(i).Amount = 0
        TradeTable.Trade2(i).Grh = 0
        TradeTable.Trade2(i).Name = vbNullString
        TradeTable.Trade2(i).Value = 0
    Next i
    TradeTable.Gold1 = 0
    TradeTable.Gold2 = 0
    TradeTable.User1Accepted = 0
    TradeTable.User2Accepted = 0
    TradeTable.User1Name = vbNullString
    TradeTable.User2Name = vbNullString
    TradeTable.MyIndex = 0

End Sub

Sub Data_Server_SendQuestInfo(ByRef rBuf As DataBuffer)
'************************************************************
'Server sent the information on a quest
'<QuestID(B)><Name(S)>(<Description(S-EX)>)
'More info: http://www.vbgore.com/GameClient.TCP.Data_Server_SendQuestInfo
'************************************************************
Dim QuestID As Byte
Dim Name As String
Dim Desc As String
Dim i As Long
Dim Changed As Byte

    'Get the variables
    QuestID = rBuf.Get_Byte
    Name = rBuf.Get_String
    If LenB(Name) <> 0 Then Desc = rBuf.Get_StringEX    'Only get the desc if the name exists

    'Resize the questinfo array if needed
    If QuestID > QuestInfoUBound Then
        QuestInfoUBound = QuestID
        ReDim Preserve QuestInfo(1 To QuestInfoUBound)
    End If
    
    'Store the information
    QuestInfo(QuestID).Name = Name
    QuestInfo(QuestID).Desc = Desc

    'Loop through the quests, remove any unused slots on the end
    If QuestInfoUBound > 1 Then
        For i = QuestInfoUBound To 1 Step -1
            If QuestInfo(i).Name = vbNullString Then
                QuestInfoUBound = QuestInfoUBound - 1
                Changed = 1
            Else
                'Exit on the first section of information
                Exit For
            End If
        Next i
        If Changed Then
            If QuestInfoUBound > 0 Then
                ReDim Preserve QuestInfo(1 To QuestInfoUBound)
            Else
                Erase QuestInfo
            End If
        End If
    Else
        If QuestInfo(1).Name = vbNullString Then
            Erase QuestInfo
            QuestInfoUBound = 0
        End If
    End If
    
End Sub
