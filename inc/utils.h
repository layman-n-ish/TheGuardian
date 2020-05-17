#pragma once
#include <chrono>
#include <random>
using namespace std;
mt19937 rng(chrono::steady_clock::now().time_since_epoch().count());

// return random number range [l,r]
int getRand(int l, int r)
{
    uniform_int_distribution<int> uid(l, r);
    return uid(rng);
}
