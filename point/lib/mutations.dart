import 'package:hooks_riverpod/experimental/mutation.dart';
import 'models/group.dart';
import 'models/item.dart';

export 'package:hooks_riverpod/experimental/mutation.dart'
    show Mutation, MutationState, MutationIdle, MutationPending, MutationSuccess, MutationError;

// Auth mutations
final loginMutation = Mutation<bool>(label: 'login');
final registerMutation = Mutation<bool>(label: 'register');
final logoutMutation = Mutation<void>(label: 'logout');
final changePasswordMutation = Mutation<void>(label: 'changePassword');
final deleteAccountMutation = Mutation<void>(label: 'deleteAccount');

// Group mutations
final createGroupMutation = Mutation<Group?>(label: 'createGroup');
final deleteGroupMutation = Mutation<void>(label: 'deleteGroup');
final joinGroupMutation = Mutation<Map<String, dynamic>>(label: 'joinGroup');
final addMemberMutation = Mutation<bool>(label: 'addMember');
final updateGroupSettingsMutation = Mutation<void>(label: 'updateGroupSettings');
final createGroupInviteMutation = Mutation<Map<String, dynamic>>(label: 'createGroupInvite');

// Sharing mutations
final sendShareRequestMutation = Mutation<bool>(label: 'sendShareRequest');
final acceptRequestMutation = Mutation<void>(label: 'acceptRequest');
final rejectRequestMutation = Mutation<void>(label: 'rejectRequest');
final removeShareMutation = Mutation<void>(label: 'removeShare');
final createTempShareMutation = Mutation<Map<String, dynamic>>(label: 'createTempShare');
final acceptZoneConsentMutation = Mutation<void>(label: 'acceptZoneConsent');
final rejectZoneConsentMutation = Mutation<void>(label: 'rejectZoneConsent');

// Item mutations
final createItemMutation = Mutation<Item?>(label: 'createItem');
