import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/providers/auth_providers.dart';
import '../../data/attempt_repository.dart';
import '../../data/reference_remote_data_source.dart';
import '../../data/reference_repository.dart';
import '../../data/video_pose_processor.dart';

final videoPoseProcessorProvider = Provider<VideoPoseProcessor>(
  (ref) => VideoPoseProcessor(),
);

final referenceRemoteDataSourceProvider = Provider<ReferenceRemoteDataSource>(
  (ref) => ReferenceRemoteDataSource(
    firestore: ref.watch(firebaseFirestoreProvider),
  ),
);

final referenceRepositoryProvider = Provider<ReferenceRepository>(
  (ref) => ReferenceRepository(
    ref.watch(videoPoseProcessorProvider),
    ref.watch(referenceRemoteDataSourceProvider),
  ),
);

final attemptRepositoryProvider = Provider<AttemptRepository>(
  (ref) => AttemptRepository(ref.watch(firebaseFirestoreProvider)),
);
