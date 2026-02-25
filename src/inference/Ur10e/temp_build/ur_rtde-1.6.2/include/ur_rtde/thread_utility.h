#pragma once
#ifndef RTDE_THREAD_UTILITY_H
#define RTDE_THREAD_UTILITY_H

#include <ur_rtde/rtde_export.h>

#include <atomic>
#include <boost/bind/bind.hpp>
#include <boost/function.hpp>
#include <boost/thread/thread.hpp>
#include <memory>

namespace ur_rtde
{
/**
 * Utility class that handles cleaning up a boost::thread
 */
class ThreadUtility
{
 private:
  std::shared_ptr<boost::thread> th_;
  std::atomic<bool> stop_thread_{false};

 public:
  ThreadUtility() = default;
  ~ThreadUtility()
  {
    stop();
  }
  ThreadUtility(const ThreadUtility &) = delete;
  ThreadUtility(ThreadUtility &&) = delete;

  /**
   * Start the thread with a given function.
   */
  void start(const boost::function<void(std::atomic<bool> *)> &f)
  {
    if (th_ != nullptr)
    {
      stop();
    }

    stop_thread_ = false;
    th_ = std::make_shared<boost::thread>(f, &stop_thread_);
  }

  /**
   * Signal for the thread to stop, but don't join the thread.
   */
  void signalStop()
  {
    stop_thread_ = true;
  }

  /**
   * Stop the thread (if it is running) and join the thread.
   */
  void stop()
  {
    stop_thread_ = true;

    // Only attempt to join the thread if it is active and is not the current thread
    if (th_ != nullptr && th_->get_id() != boost::this_thread::get_id())
    {
      if (th_->joinable())
      {
        th_->interrupt();
        th_->join();
      }
      th_ = nullptr;
    }
  }
};
};  // namespace ur_rtde

#endif