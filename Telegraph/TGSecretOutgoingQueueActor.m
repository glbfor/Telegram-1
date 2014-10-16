#import "TGSecretOutgoingQueueActor.h"

#import <MTProtoKit/MTRequest.h>

#import "TGDatabase.h"
#import "TL/TLMetaScheme.h"

#import "ActionStage.h"

#import "TGTelegramNetworking.h"

#import "TGModernSendSecretMessageActor.h"

@interface TGSecretOutgoingRequest : MTRequest

@property (nonatomic) int32_t actionId;
@property (nonatomic) int32_t seqOut;
@property (nonatomic) bool isResend;

@end

@implementation TGSecretOutgoingRequest

@end

@interface TGSecretOutgoingQueueActor ()
{
    int64_t _peerId;
    int64_t _encryptedChatId;
    int64_t _accessHash;
    NSData *_key;
    int64_t _keyId;
    bool _isCreator;
    
    NSMutableSet *_executingRequestsActionIds;
}

@end

@implementation TGSecretOutgoingQueueActor

+ (void)load
{
    [ASActor registerActorClass:self];
}

+ (NSString *)genericPath
{
    return @"/tg/secret/outgoing/@";
}

- (void)execute:(NSDictionary *)options
{
    _peerId = (int64_t)[options[@"peerId"] longLongValue];
    _encryptedChatId = [TGDatabaseInstance() encryptedConversationIdForPeerId:_peerId];
    _accessHash = [TGDatabaseInstance() encryptedConversationAccessHash:_peerId];
    _key = [TGDatabaseInstance() encryptionKeyForConversationId:_peerId keyFingerprint:&_keyId];
    _isCreator = [TGDatabaseInstance() encryptedConversationIsCreator:_peerId];
    
    if (_accessHash == 0)
        [ActionStageInstance() actionFailed:self.path reason:-1];
    else
    {
        _executingRequestsActionIds = [[NSMutableSet alloc] init];
        
        [self _poll];
    }
}

- (void)watcherJoined:(ASHandle *)watcherHandle options:(NSDictionary *)options waitingInActorQueue:(bool)waitingInActorQueue
{
    [super watcherJoined:watcherHandle options:options waitingInActorQueue:waitingInActorQueue];
    
    [self _poll];
}

- (void)_poll
{
    [TGDatabaseInstance() dequeuePeerOutgoingActions:_peerId completion:^(NSArray *actions, NSArray *resendActions)
    {
        [ActionStageInstance() dispatchOnStageQueue:^
        {
            NSMutableArray *requests = [[NSMutableArray alloc] init];
            
            NSInteger index = -1;
            for (TGStoredSecretActionWithSeq *action in [actions arrayByAddingObjectsFromArray:resendActions])
            {
                index++;
                
                if ([_executingRequestsActionIds containsObject:@(action.actionId)])
                    continue;
                
                TGSecretOutgoingRequest *request = [self requestForAction:action.action actionId:action.actionId seqIn:action.seqIn seqOut:action.seqOut isResend:index >= (NSInteger)actions.count];
                if (request != nil)
                {
                    __weak TGSecretOutgoingQueueActor *weakSelf = self;
                    int32_t seqOut = action.seqOut;
                    int32_t actionId = action.actionId;
                    int32_t actionSeqOut = request.seqOut;
                    bool isResend = request.isResend;
                    [request setCompleted:^(id result, NSTimeInterval timestamp, id error)
                    {
                        __strong TGSecretOutgoingQueueActor *strongSelf = weakSelf;
                        if (strongSelf != nil)
                        {
                            if (error == nil)
                                [strongSelf actionCompletedWithId:actionId date:(int32_t)(timestamp * 4294967296.0) result:result actionSeqOut:actionSeqOut isResend:isResend];
                            else
                            {
                                TGLog(@"something's went terribly wrong");
                            }
                        }
                    }];
                    
                    [request setAcknowledgementReceived:^
                    {
                        __strong TGSecretOutgoingQueueActor *strongSelf = weakSelf;
                        if (strongSelf != nil)
                            [strongSelf actionQuickAck:actionId];
                    }];
                    
                    [request setShouldDependOnRequest:^bool(MTRequest *other)
                    {
                        if ([other isKindOfClass:[TGSecretOutgoingRequest class]])
                        {
                            return ((TGSecretOutgoingRequest *)other).seqOut < seqOut;
                        }
                        
                        return false;
                    }];
                    
                    [requests addObject:request];
                }
            }
            
            for (TGSecretOutgoingRequest *request in requests)
            {
                [[TGTelegramNetworking instance] addRequest:request];
                [_executingRequestsActionIds addObject:@(request.actionId)];
            }
        }];
    }];
}

- (void)actionCompletedWithId:(int32_t)actionId date:(int32_t)date result:(id)result actionSeqOut:(int32_t)actionSeqOut isResend:(bool)isResend
{
    [ActionStageInstance() dispatchOnStageQueue:^
    {
        if (isResend)
            [TGDatabaseInstance() deletePeerOutgoingResendActions:_peerId actionIds:@[@(actionId)]];
        else if (actionSeqOut >= 0)
            [TGDatabaseInstance() applyPeerSeqOut:_peerId seqOut:actionSeqOut];
        else
            [TGDatabaseInstance() deletePeerOutgoingActions:_peerId actionIds:@[@(actionId)]];
        
        [ActionStageInstance() dispatchMessageToWatchers:self.path messageType:@"actionCompletedWithSeq" message:@{@"actionId": @(actionId), @"date": @(date), @"result": result}];
    }];
}

- (void)actionQuickAck:(int32_t)actionId
{
    [ActionStageInstance() dispatchMessageToWatchers:self.path messageType:@"actionQuickAck" message:@{@"actionId": @(actionId)}];
}

- (TGSecretOutgoingRequest *)requestForAction:(id)action actionId:(int32_t)actionId seqIn:(int32_t)seqIn seqOut:(int32_t)seqOut isResend:(bool)isResend
{
    if ([action isKindOfClass:[TGStoredOutgoingMessageSecretAction class]])
    {
        TGStoredOutgoingMessageSecretAction *concreteAction = action;
        
        NSData *messageData = nil;
        NSData *actionData = nil;
        
        for (TGModernSendSecretMessageActor *actor in [ActionStageInstance() executingActorsWithPathPrefix:@"/tg/sendSecretMessage/"])
        {
            if ([actor waitsForActionWithId:actionId])
            {
                actionData = concreteAction.data;
                break;
            }
        }
        
        if (actionData == nil)
        {
            actionData = [TGModernSendSecretMessageActor decryptedServiceMessageActionWithLayer:concreteAction.layer deleteMessagesWithRandomIds:@[@(concreteAction.randomId)] randomId:concreteAction.randomId];
        }
        
        if (concreteAction.layer >= 17)
        {
            NSMutableData *data = [[NSMutableData alloc] init];
            int32_t constructorSignature = 0x1be31789;
            [data appendBytes:&constructorSignature length:4];
            
            uint8_t randomBytesLength = 15;
            [data appendBytes:&randomBytesLength length:1];
            
            uint8_t randomBytes[15];
            arc4random_buf(randomBytes, 15);
            [data appendBytes:randomBytes length:15];
            
            int32_t layer = (int32_t)concreteAction.layer;
            [data appendBytes:&layer length:4];
            
            int32_t inSeqNo = seqIn * 2 + (_isCreator ? 0 : 1);
            [data appendBytes:&inSeqNo length:4];
            
            int32_t outSeqNo = seqOut * 2 + (_isCreator ? 1 : 0);
            [data appendBytes:&outSeqNo length:4];
            
            [data appendData:actionData];
            
            messageData = [TGModernSendSecretMessageActor encryptMessage:data key:_key keyId:_keyId];
        }
        else
            messageData = [TGModernSendSecretMessageActor encryptMessage:actionData key:_key keyId:_keyId];
        
        TGSecretOutgoingRequest *request = [[TGSecretOutgoingRequest alloc] init];
        request.actionId = actionId;
        request.isResend = isResend;
        request.seqOut = concreteAction.layer >= 17 ? seqOut : -1;
        
        if (concreteAction.fileInfo == nil)
        {
            TLRPCmessages_sendEncrypted$messages_sendEncrypted *sendEncrypted = [[TLRPCmessages_sendEncrypted$messages_sendEncrypted alloc] init];
            
            TLInputEncryptedChat$inputEncryptedChat *inputEncryptedChat = [[TLInputEncryptedChat$inputEncryptedChat alloc] init];
            inputEncryptedChat.chat_id = (int32_t)_encryptedChatId;
            inputEncryptedChat.access_hash = _accessHash;
            sendEncrypted.peer = inputEncryptedChat;
            
            sendEncrypted.random_id = concreteAction.randomId;
            sendEncrypted.data = messageData;
            
            request.body = sendEncrypted;
        }
        else
        {
            TLRPCmessages_sendEncryptedFile$messages_sendEncryptedFile *sendEncrypted = [[TLRPCmessages_sendEncryptedFile$messages_sendEncryptedFile alloc] init];
            
            TLInputEncryptedChat$inputEncryptedChat *inputEncryptedChat = [[TLInputEncryptedChat$inputEncryptedChat alloc] init];
            inputEncryptedChat.chat_id = (int32_t)_encryptedChatId;
            inputEncryptedChat.access_hash = _accessHash;
            sendEncrypted.peer = inputEncryptedChat;
            
            sendEncrypted.random_id = concreteAction.randomId;
            sendEncrypted.data = messageData;
            
            if ([concreteAction.fileInfo isKindOfClass:[TGStoredOutgoingMessageFileInfoUploaded class]])
            {
                TGStoredOutgoingMessageFileInfoUploaded *fileInfo = (TGStoredOutgoingMessageFileInfoUploaded *)concreteAction.fileInfo;
                TLInputEncryptedFile$inputEncryptedFileUploaded *schemaFileInfo = [[TLInputEncryptedFile$inputEncryptedFileUploaded alloc] init];
                schemaFileInfo.n_id = fileInfo.n_id;
                schemaFileInfo.parts = fileInfo.parts;
                schemaFileInfo.md5_checksum = fileInfo.md5_checksum;
                schemaFileInfo.key_fingerprint = fileInfo.key_fingerprint;
                
                sendEncrypted.file = schemaFileInfo;
            }
            else if ([concreteAction.fileInfo isKindOfClass:[TGStoredOutgoingMessageFileInfoExisting class]])
            {
                TGStoredOutgoingMessageFileInfoExisting *fileInfo = (TGStoredOutgoingMessageFileInfoExisting *)concreteAction.fileInfo;
                TLInputEncryptedFile$inputEncryptedFile *schemaFileInfo = [[TLInputEncryptedFile$inputEncryptedFile alloc] init];
                schemaFileInfo.n_id = fileInfo.n_id;
                schemaFileInfo.access_hash = fileInfo.access_hash;
                
                sendEncrypted.file = schemaFileInfo;
            }
            else if ([concreteAction.fileInfo isKindOfClass:[TGStoredOutgoingMessageFileInfoBigUploaded class]])
            {
                TGStoredOutgoingMessageFileInfoBigUploaded *fileInfo = (TGStoredOutgoingMessageFileInfoBigUploaded *)concreteAction.fileInfo;
                TLInputEncryptedFile$inputEncryptedFileBigUploaded *schemaFileInfo = [[TLInputEncryptedFile$inputEncryptedFileBigUploaded alloc] init];
                schemaFileInfo.n_id = fileInfo.n_id;
                schemaFileInfo.parts = fileInfo.parts;
                schemaFileInfo.key_fingerprint = fileInfo.key_fingerprint;
                
                sendEncrypted.file = schemaFileInfo;
            }
            
            request.body = sendEncrypted;
        }
        
        return request;
    }
    else if ([action isKindOfClass:[TGStoredOutgoingServiceMessageSecretAction class]])
    {
        TGStoredOutgoingServiceMessageSecretAction *concreteAction = action;
        
        NSData *messageData = nil;
        
        if (concreteAction.layer >= 17)
        {
            NSMutableData *data = [[NSMutableData alloc] init];
            int32_t constructorSignature = 0x1be31789;
            [data appendBytes:&constructorSignature length:4];
            
            uint8_t randomBytesLength = 15;
            [data appendBytes:&randomBytesLength length:1];
            
            uint8_t randomBytes[15];
            arc4random_buf(randomBytes, 15);
            [data appendBytes:randomBytes length:15];
            
            int32_t layer = (int32_t)concreteAction.layer;
            [data appendBytes:&layer length:4];
            
            int32_t inSeqNo = seqIn * 2 + (_isCreator ? 0 : 1);
            [data appendBytes:&inSeqNo length:4];
            
            int32_t outSeqNo = seqOut * 2 + (_isCreator ? 1 : 0);
            [data appendBytes:&outSeqNo length:4];
            
            [data appendData:concreteAction.data];
            
            messageData = [TGModernSendSecretMessageActor encryptMessage:data key:_key keyId:_keyId];
        }
        else
            messageData = [TGModernSendSecretMessageActor encryptMessage:concreteAction.data key:_key keyId:_keyId];
        
        TGSecretOutgoingRequest *request = [[TGSecretOutgoingRequest alloc] init];
        request.actionId = actionId;
        request.isResend = isResend;
        request.seqOut = concreteAction.layer >= 17 ? seqOut : -1;
        
        TLRPCmessages_sendEncryptedService$messages_sendEncryptedService *sendEncryptedService = [[TLRPCmessages_sendEncryptedService$messages_sendEncryptedService alloc] init];
        
        TLInputEncryptedChat$inputEncryptedChat *inputEncryptedChat = [[TLInputEncryptedChat$inputEncryptedChat alloc] init];
        inputEncryptedChat.chat_id = (int32_t)_encryptedChatId;
        inputEncryptedChat.access_hash = _accessHash;
        sendEncryptedService.peer = inputEncryptedChat;
        
        sendEncryptedService.random_id = concreteAction.randomId;
        sendEncryptedService.data = messageData;
        
        request.body = sendEncryptedService;
        
        return request;
    }
    
    return nil;
}

@end
